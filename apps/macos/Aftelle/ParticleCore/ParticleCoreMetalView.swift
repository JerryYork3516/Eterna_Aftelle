import AppKit
import MetalKit
import SwiftUI
import simd

struct ParticleViewOrientation: Equatable {
    let quaternion: SIMD4<Float>

    static let identity = ParticleViewOrientation(
        quaternion: SIMD4<Float>(0, 0, 0, 1)
    )

    init(quaternion: SIMD4<Float>) {
        let length = simd_length(quaternion)
        self.quaternion = length > ParticleTuning.Engine.quaternionNormalizationEpsilon
            ? quaternion / length
            : SIMD4<Float>(0, 0, 0, 1)
    }
}

struct ParticleCoreMetalView: NSViewRepresentable {
    var visualIntent: ResidentVisualIntent = .idle
    var speechSignal: ResidentSpeechSignal = .inactive
    var expressionInput: ParticleExpressionInput = .neutral
    var isDebugSpeechOverrideActive = false
    var shapeTarget: ParticleShapeTarget = .sphere
    var tuning: ParticleTuning = .systemDefault
    var colorProfile: ParticleColorProfile = .systemDefault
    var rebuildGeneration = 0
    var isManualRotationEnabled = false
    var viewOrientation: ParticleViewOrientation = .identity
    var debugVisualIntent: ResidentVisualIntent?
    var debugIntentGeneration = 0
    var isDebugAutoCycleEnabled = false
    var debugStressTestGeneration = 0
    var debugShapeMorphDuration =
        ParticleShapeMorphTuning.defaultDuration
    var isTransparentBackground = false
    var debugMetricsHandler: ((ParticleRenderMetrics) -> Void)?
    var debugRebuildCountHandler: ((Int) -> Void)?
    var viewOrientationHandler: ((ParticleViewOrientation) -> Void)?
    var effectiveViewOrientationHandler: ((ParticleViewOrientation) -> Void)?

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[ParticleCore] metal device missing")
            return MTKView(frame: .zero, device: nil)
        }

        let view = ParticleCoreInputView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = ParticleTuning.Engine.preferredFramesPerSecond
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true
        configureBackground(for: view, transparent: isTransparentBackground)

        guard let renderer = ParticleRenderer(device: device, visualIntent: visualIntent) else {
            print("[ParticleCore] renderer init failed")
            return view
        }
        view.inputRenderer = renderer
        view.setManualRotationEnabled(isManualRotationEnabled)
        view.delegate = renderer
        context.coordinator.renderer = renderer
        context.coordinator.swiftUIVisualIntent = visualIntent
        context.coordinator.speechSignal = speechSignal
        context.coordinator.expressionInput = expressionInput
        context.coordinator.shapeTarget = shapeTarget
        context.coordinator.tuning = tuning
        context.coordinator.colorProfile = colorProfile
        context.coordinator.rebuildGeneration = rebuildGeneration
        context.coordinator.isManualRotationEnabled = isManualRotationEnabled
        context.coordinator.viewOrientation = viewOrientation
        context.coordinator.debugVisualIntent = debugVisualIntent
        context.coordinator.debugIntentGeneration = debugIntentGeneration
        context.coordinator.isDebugAutoCycleEnabled = isDebugAutoCycleEnabled
        context.coordinator.debugStressTestGeneration = debugStressTestGeneration
        context.coordinator.debugShapeMorphDuration =
            debugShapeMorphDuration
        context.coordinator.debugMetricsHandler = debugMetricsHandler
        context.coordinator.debugRebuildCountHandler =
            debugRebuildCountHandler
        context.coordinator.viewOrientationHandler = viewOrientationHandler
        view.viewOrientationHandler = { orientation in
            context.coordinator.viewOrientation = orientation
            DispatchQueue.main.async {
                context.coordinator.viewOrientationHandler?(orientation)
            }
        }
        renderer.debugMetricsHandler = { metrics in
            DispatchQueue.main.async {
                context.coordinator.debugMetricsHandler?(metrics)
            }
        }
        renderer.debugRebuildCountHandler = { count in
            DispatchQueue.main.async {
                context.coordinator.debugRebuildCountHandler?(count)
            }
        }
        context.coordinator.setEffectiveViewOrientationHandler(
            effectiveViewOrientationHandler
        )
        renderer.setTuning(tuning)
        renderer.setColorProfile(colorProfile)
        renderer.setViewOrientation(viewOrientation)
        renderer.setManualRotationEnabled(isManualRotationEnabled)
        renderer.setShapeTarget(shapeTarget)
        renderer.setExpressionInput(expressionInput)
        renderer.setSpeechSignal(
            speechSignal,
            reason: isDebugSpeechOverrideActive
                ? "debugPanel.speech"
                : "appSpeech"
        )
        #if DEBUG
        renderer.setDebugShapeMorphDuration(debugShapeMorphDuration)
        renderer.setDebugAutoCycleEnabled(isDebugAutoCycleEnabled)
        if let debugVisualIntent {
            renderer.setVisualIntent(debugVisualIntent, reason: "debugPanel.initial")
        }
        #endif
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        configureBackground(for: nsView, transparent: isTransparentBackground)
        let debugOverrideActive = debugVisualIntent != nil || isDebugAutoCycleEnabled
        if context.coordinator.swiftUIVisualIntent != visualIntent {
            if !debugOverrideActive {
                context.coordinator.renderer?.setVisualIntent(visualIntent, reason: "appMapping")
            }
            context.coordinator.swiftUIVisualIntent = visualIntent
        }
        if context.coordinator.speechSignal != speechSignal {
            context.coordinator.renderer?.setSpeechSignal(
                speechSignal,
                reason: isDebugSpeechOverrideActive
                    ? "debugPanel.speech"
                    : "appSpeech"
            )
            context.coordinator.speechSignal = speechSignal
        }
        if context.coordinator.expressionInput != expressionInput {
            context.coordinator.renderer?.setExpressionInput(expressionInput)
            context.coordinator.expressionInput = expressionInput
        }
        if context.coordinator.shapeTarget != shapeTarget {
            #if DEBUG
            context.coordinator.renderer?.setDebugShapeTarget(
                shapeTarget,
                reason: "debugPanel.shape"
            )
            #else
            context.coordinator.renderer?.setShapeTarget(
                shapeTarget,
                reason: "appShape"
            )
            #endif
            context.coordinator.shapeTarget = shapeTarget
        }
        #if DEBUG
        if context.coordinator.debugShapeMorphDuration
            != debugShapeMorphDuration {
            context.coordinator.renderer?.setDebugShapeMorphDuration(
                debugShapeMorphDuration
            )
            context.coordinator.debugShapeMorphDuration =
                debugShapeMorphDuration
        }
        if context.coordinator.isDebugAutoCycleEnabled != isDebugAutoCycleEnabled {
            context.coordinator.renderer?.setDebugAutoCycleEnabled(
                isDebugAutoCycleEnabled
            )
            context.coordinator.isDebugAutoCycleEnabled = isDebugAutoCycleEnabled
            if !isDebugAutoCycleEnabled, debugVisualIntent == nil {
                context.coordinator.renderer?.setVisualIntent(
                    visualIntent,
                    reason: "debugPanel.followRuntime"
                )
            }
        }
        if context.coordinator.debugIntentGeneration != debugIntentGeneration {
            context.coordinator.renderer?.setVisualIntent(
                debugVisualIntent ?? visualIntent,
                reason: debugVisualIntent == nil
                    ? "debugPanel.followRuntime"
                    : "debugPanel.state"
            )
            context.coordinator.debugVisualIntent = debugVisualIntent
            context.coordinator.debugIntentGeneration = debugIntentGeneration
        }
        if context.coordinator.debugStressTestGeneration
            != debugStressTestGeneration {
            context.coordinator.renderer?.runDebugTransitionStressTest()
            context.coordinator.debugStressTestGeneration = debugStressTestGeneration
        }
        #endif
        context.coordinator.debugMetricsHandler = debugMetricsHandler
        context.coordinator.debugRebuildCountHandler =
            debugRebuildCountHandler
        context.coordinator.setEffectiveViewOrientationHandler(
            effectiveViewOrientationHandler
        )
        if context.coordinator.tuning != tuning {
            context.coordinator.renderer?.setTuning(tuning)
            context.coordinator.tuning = tuning
        }
        if context.coordinator.colorProfile != colorProfile {
            context.coordinator.renderer?.setColorProfile(colorProfile)
            context.coordinator.colorProfile = colorProfile
        }
        if context.coordinator.rebuildGeneration != rebuildGeneration {
            context.coordinator.renderer?.rebuildParticles()
            context.coordinator.rebuildGeneration = rebuildGeneration
        }
        context.coordinator.viewOrientationHandler = viewOrientationHandler
        if context.coordinator.viewOrientation != viewOrientation {
            context.coordinator.renderer?.setViewOrientation(viewOrientation)
            context.coordinator.viewOrientation = viewOrientation
        }
        if context.coordinator.isManualRotationEnabled != isManualRotationEnabled {
            context.coordinator.renderer?.setManualRotationEnabled(isManualRotationEnabled)
            (nsView as? ParticleCoreInputView)?
                .setManualRotationEnabled(isManualRotationEnabled)
            context.coordinator.isManualRotationEnabled = isManualRotationEnabled
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configureBackground(for view: MTKView, transparent: Bool) {
        if transparent {
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.isOpaque = false
        } else {
            view.clearColor = MTLClearColor(red: 0.035, green: 0.04, blue: 0.05, alpha: 1)
            view.layer?.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.04, blue: 0.05, alpha: 1).cgColor
            view.layer?.isOpaque = true
        }
    }

    final class Coordinator {
        var renderer: ParticleRenderer?
        var swiftUIVisualIntent: ResidentVisualIntent = .idle
        var speechSignal: ResidentSpeechSignal = .inactive
        var expressionInput: ParticleExpressionInput = .neutral
        var shapeTarget: ParticleShapeTarget = .sphere
        var tuning: ParticleTuning = .systemDefault
        var colorProfile: ParticleColorProfile = .systemDefault
        var rebuildGeneration = 0
        var isManualRotationEnabled = false
        var viewOrientation: ParticleViewOrientation = .identity
        var debugVisualIntent: ResidentVisualIntent?
        var debugIntentGeneration = 0
        var isDebugAutoCycleEnabled = false
        var debugStressTestGeneration = 0
        var debugShapeMorphDuration =
            ParticleShapeMorphTuning.defaultDuration
        var debugMetricsHandler: ((ParticleRenderMetrics) -> Void)?
        var debugRebuildCountHandler: ((Int) -> Void)?
        var viewOrientationHandler: ((ParticleViewOrientation) -> Void)?
        var effectiveViewOrientationHandler: ((ParticleViewOrientation) -> Void)?
        private var isEffectiveViewOrientationHandlerEnabled = false

        func setEffectiveViewOrientationHandler(
            _ handler: ((ParticleViewOrientation) -> Void)?
        ) {
            effectiveViewOrientationHandler = handler
            let isEnabled = handler != nil
            guard isEffectiveViewOrientationHandlerEnabled != isEnabled else {
                return
            }
            isEffectiveViewOrientationHandlerEnabled = isEnabled
            guard isEnabled else {
                renderer?.effectiveViewOrientationHandler = nil
                return
            }
            renderer?.effectiveViewOrientationHandler = { [weak self] orientation in
                DispatchQueue.main.async { [weak self] in
                    self?.effectiveViewOrientationHandler?(orientation)
                }
            }
        }
    }
}

private final class ParticleCoreInputView: MTKView {
    weak var inputRenderer: ParticleRenderer?
    private var trackingAreaRef: NSTrackingArea?
    private var lastMousePosition: SIMD2<Float>?
    private var lastMouseTime: TimeInterval?
    private var isManualRotationEnabled = false
    private var lastManualDragLocation: CGPoint?
    var viewOrientationHandler: ((ParticleViewOrientation) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        updateMouse(with: event, active: true)
    }

    override func mouseDragged(with event: NSEvent) {
        if isManualRotationEnabled {
            rotateView(with: event)
            return
        }
        updateMouse(with: event, active: true)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isManualRotationEnabled {
            lastManualDragLocation = convert(event.locationInWindow, from: nil)
            inputRenderer?.updateInteraction(
                position: .zero,
                velocity: .zero,
                active: false
            )
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isManualRotationEnabled {
            lastManualDragLocation = nil
            return
        }
        super.mouseUp(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        lastManualDragLocation = nil
        lastMousePosition = nil
        lastMouseTime = nil
        inputRenderer?.updateInteraction(position: .zero, velocity: .zero, active: false)
    }

    override func keyDown(with event: NSEvent) {
        #if DEBUG
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }

        switch key {
        case "i":
            inputRenderer?.setVisualIntent(.idle, reason: "debugKey.I")
        case "n":
            inputRenderer?.setVisualIntent(.listening, reason: "debugKey.N")
        case "t":
            inputRenderer?.setVisualIntent(.thinking, reason: "debugKey.T")
        case "s":
            inputRenderer?.setVisualIntent(.speaking, reason: "debugKey.S")
        case "z":
            inputRenderer?.setVisualIntent(.sleeping, reason: "debugKey.Z")
        case "l":
            inputRenderer?.setVisualIntent(.loading, reason: "debugKey.L")
        case "e":
            inputRenderer?.setVisualIntent(.error, reason: "debugKey.E")
        case "x":
            inputRenderer?.setVisualIntent(.exit, reason: "debugKey.X")
        default:
            super.keyDown(with: event)
        }
        #else
        super.keyDown(with: event)
        #endif
    }

    func setManualRotationEnabled(_ enabled: Bool) {
        isManualRotationEnabled = enabled
        if !enabled {
            lastManualDragLocation = nil
        }
    }

    private func rotateView(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let lastManualDragLocation else {
            self.lastManualDragLocation = location
            return
        }

        self.lastManualDragLocation = location
        guard let orientation = inputRenderer?.rotateView(
            fromArcballPoint: arcballPoint(lastManualDragLocation),
            to: arcballPoint(location)
        ) else {
            return
        }
        viewOrientationHandler?(orientation)
    }

    private func arcballPoint(_ point: CGPoint) -> SIMD2<Float> {
        let radius = max(
            min(bounds.width, bounds.height)
                * 0.5
                * ParticleTuning.Engine.manualRotationArcballRadiusScale,
            1
        )
        return SIMD2<Float>(
            Float((point.x - bounds.midX) / radius),
            Float((point.y - bounds.midY) / radius)
        )
    }

    private func updateMouse(with event: NSEvent, active: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.width > 1, bounds.height > 1 else { return }

        let aspect = Float(bounds.width / max(bounds.height, 1))
        let position = SIMD2<Float>(
            (Float(point.x / bounds.width) * 2 - 1) * aspect,
            Float(point.y / bounds.height) * 2 - 1
        )

        let timestamp = event.timestamp
        let velocity: SIMD2<Float>
        if let lastMousePosition, let lastMouseTime {
            let dt = max(Float(timestamp - lastMouseTime), 0.008)
            let rawVelocity = (position - lastMousePosition) / dt
            velocity = SIMD2<Float>(
                max(-5, min(5, rawVelocity.x)),
                max(-5, min(5, rawVelocity.y))
            )
        } else {
            velocity = .zero
        }

        lastMousePosition = position
        lastMouseTime = timestamp
        inputRenderer?.updateInteraction(position: position, velocity: velocity, active: active)
    }
}
