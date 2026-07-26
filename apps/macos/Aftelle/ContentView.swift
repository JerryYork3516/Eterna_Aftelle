import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import simd

#if DEBUG
@MainActor
final class ParticleOrientationOverlayState: ObservableObject {
    @Published private(set) var orientation: ParticleViewOrientation = .identity

    func update(_ orientation: ParticleViewOrientation) {
        self.orientation = orientation
    }
}
#endif

@MainActor
final class ParticlePresentationSettings: ObservableObject {
    @Published var tuning = ParticleTuning.loadSaved()
    @Published var colorProfile = ParticleColorProfile.loadSaved() ?? .systemDefault
    @Published private(set) var rebuildGeneration = 0
    @Published var isManualRotationEnabled = false
    @Published var viewOrientation: ParticleViewOrientation = .identity
    @Published private(set) var debugVisualIntent: ResidentVisualIntent?
    @Published private(set) var debugIntentGeneration = 0
    @Published private(set) var isDebugAutoCycleEnabled = false
    @Published private(set) var debugStressTestGeneration = 0
    @Published private(set) var debugSpeechSignal: ResidentSpeechSignal?
    @Published private(set) var shapeTarget: ParticleShapeTarget = .sphere
    @Published private(set) var debugSpeechIntensity = Double(
        ParticleTuning.Engine.defaultSpeechIntensity
    )
    #if DEBUG
    @Published var isOrientationOverlayVisible = false
    let orientationOverlayState = ParticleOrientationOverlayState()
    #endif

    func rebuildWithFixedSeed() {
        rebuildGeneration &+= 1
    }

    func updateViewOrientation(_ orientation: ParticleViewOrientation) {
        viewOrientation = orientation
    }

    func resetViewOrientation() {
        viewOrientation = .identity
        #if DEBUG
        orientationOverlayState.update(.identity)
        #endif
    }

    func selectDebugVisualIntent(_ intent: ResidentVisualIntent) {
        isDebugAutoCycleEnabled = false
        debugVisualIntent = intent
        debugIntentGeneration &+= 1
    }

    func setDebugAutoCycleEnabled(_ enabled: Bool) {
        isDebugAutoCycleEnabled = enabled
        if enabled {
            debugVisualIntent = nil
        }
    }

    func followRuntimeVisualIntent() {
        isDebugAutoCycleEnabled = false
        debugVisualIntent = nil
        debugIntentGeneration &+= 1
    }

    func runDebugTransitionStressTest() {
        debugStressTestGeneration &+= 1
    }

    func selectDebugShapeTarget(_ target: ParticleShapeTarget) {
        guard target.isImplemented else { return }
        shapeTarget = target
    }

    func simulateDebugSpeech(_ phase: ResidentSpeechPhase) {
        let intensity: Float
        switch phase {
        case .started, .sustained:
            intensity = Float(debugSpeechIntensity)
        case .inactive, .paused, .ended:
            intensity = 0
        }
        debugSpeechSignal = ResidentSpeechSignal(
            phase: phase,
            intensity: intensity
        )
    }

    func setDebugSpeechIntensity(_ intensity: Double) {
        debugSpeechIntensity = min(1, max(0, intensity))
        guard let signal = debugSpeechSignal,
              signal.phase == .started || signal.phase == .sustained else {
            return
        }
        simulateDebugSpeech(signal.phase)
    }

    func followRuntimeSpeech() {
        debugSpeechSignal = nil
    }
}

struct ContentView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var presentationSettings: ParticlePresentationSettings
    @State private var residentInputText = ""
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var debugSubtitleKeyMonitor: Any?
    #endif

    var body: some View {
        ZStack {
            shellBackground
                .ignoresSafeArea()

            ParticleCoreMetalView(
                visualIntent: controller.residentVisualIntent,
                speechSignal: presentationSettings.debugSpeechSignal
                    ?? controller.residentSpeechSignal,
                isDebugSpeechOverrideActive:
                    presentationSettings.debugSpeechSignal != nil,
                shapeTarget: presentationSettings.shapeTarget,
                tuning: presentationSettings.tuning,
                colorProfile: presentationSettings.colorProfile,
                rebuildGeneration: presentationSettings.rebuildGeneration,
                isManualRotationEnabled: presentationSettings.isManualRotationEnabled,
                viewOrientation: presentationSettings.viewOrientation,
                debugVisualIntent: presentationSettings.debugVisualIntent,
                debugIntentGeneration: presentationSettings.debugIntentGeneration,
                isDebugAutoCycleEnabled: presentationSettings.isDebugAutoCycleEnabled,
                debugStressTestGeneration: presentationSettings.debugStressTestGeneration,
                isTransparentBackground: controller.particleShellMode == .transparentShell,
                debugMetricsHandler: { metrics in
                    controller.updateParticleRenderMetrics(metrics)
                },
                viewOrientationHandler: presentationSettings.updateViewOrientation,
                effectiveViewOrientationHandler: effectiveViewOrientationHandler
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()
                ParticleSubtitleOverlay(state: controller.particleSubtitleState)
                ResidentTextInputBar(
                    text: $residentInputText,
                    state: controller.residentTextInputState,
                    isResidentAvailable: controller.isResidentTextInputAvailable,
                    submit: controller.submitResidentText
                )
            }

            #if DEBUG
            if presentationSettings.isOrientationOverlayVisible {
                ParticleOrientationDebugOverlay(
                    state: presentationSettings.orientationOverlayState
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowShellConfigurator(shellMode: controller.particleShellMode))
        .task {
            controller.start()
        }
        .onChange(of: controller.particleColorProfile) { _, newValue in
            guard !ParticleColorProfile.hasSavedProfile() else { return }
            presentationSettings.colorProfile = newValue
            controller.updateEffectiveParticleColorProfile(newValue, savedOverride: false)
        }
        .onChange(of: presentationSettings.colorProfile) { _, newValue in
            controller.updateEffectiveParticleColorProfile(
                newValue,
                savedOverride: ParticleColorProfile.hasSavedProfile()
            )
        }
        .onChange(of: controller.sessionState.sessionID) { _, _ in
            residentInputText = ""
        }
        #if DEBUG
        .onAppear {
            controller.updateEffectiveParticleColorProfile(
                presentationSettings.colorProfile,
                savedOverride: ParticleColorProfile.hasSavedProfile()
            )
            installDebugSubtitleKeyMonitor()
        }
        .onDisappear {
            removeDebugSubtitleKeyMonitor()
        }
        .onChange(of: controller.isParticleDebugPanelPresented) { _, isPresented in
            if isPresented {
                openWindow(id: ParticleDebugWindow.sceneID)
            } else {
                dismissWindow(id: ParticleDebugWindow.sceneID)
            }
        }
        #endif
    }

    private var effectiveViewOrientationHandler:
        ((ParticleViewOrientation) -> Void)? {
        #if DEBUG
        guard presentationSettings.isOrientationOverlayVisible else { return nil }
        return presentationSettings.orientationOverlayState.update
        #else
        return nil
        #endif
    }

    private var shellBackground: Color {
        switch controller.particleShellMode {
        case .darkShell:
            return Color(red: 0.045, green: 0.05, blue: 0.06)
        case .immersiveShell:
            return Color(red: 0.026, green: 0.030, blue: 0.036)
        case .transparentShell:
            return .clear
        }
    }

    #if DEBUG
    private func installDebugSubtitleKeyMonitor() {
        guard debugSubtitleKeyMonitor == nil else { return }
        debugSubtitleKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  (event.window?.firstResponder as? NSTextView) == nil,
                  let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }

            switch key {
            case "c":
                controller.showDebugSubtitle()
                return nil
            case "v":
                controller.showNextDebugSubtitle()
                return nil
            case "b":
                controller.hideDebugSubtitle()
                return nil
            default:
                return event
            }
        }
    }

    private func removeDebugSubtitleKeyMonitor() {
        if let debugSubtitleKeyMonitor {
            NSEvent.removeMonitor(debugSubtitleKeyMonitor)
            self.debugSubtitleKeyMonitor = nil
        }
    }
    #endif
}

private struct WindowShellConfigurator: NSViewRepresentable {
    let shellMode: ParticleShellMode

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let immersive = shellMode == .immersiveShell
            let transparent = shellMode == .transparentShell
            let visualShell = immersive || transparent
            if visualShell {
                window.styleMask.insert(.fullSizeContentView)
            } else {
                window.styleMask.remove(.fullSizeContentView)
            }
            if transparent {
                window.styleMask.remove(.titled)
            } else {
                window.styleMask.insert(.titled)
            }
            window.titleVisibility = visualShell ? .hidden : .visible
            window.titlebarAppearsTransparent = visualShell
            window.isOpaque = !transparent
            window.backgroundColor = transparent ? .clear : NSColor(calibratedRed: 0.045, green: 0.05, blue: 0.06, alpha: 1)
            window.hasShadow = !transparent
            window.standardWindowButton(.closeButton)?.isHidden = visualShell
            window.standardWindowButton(.miniaturizeButton)?.isHidden = visualShell
            window.standardWindowButton(.zoomButton)?.isHidden = visualShell
        }
    }
}

private struct ParticleSubtitleOverlay: View {
    let state: ParticleSubtitleState

    var body: some View {
        if !state.text.isEmpty {
            ScrollView(.vertical) {
                Text(state.text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.36), radius: 8, x: 0, y: 2)
            }
            .id(state.text)
            .frame(maxWidth: 560, maxHeight: 112)
            .padding(.horizontal, 28)
            .opacity(state.phase == .fading ? 0 : 1)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.28), value: state)
        }
    }
}

private struct ResidentTextInputBar: View {
    @Binding var text: String
    let state: ResidentTextInputViewState
    let isResidentAvailable: Bool
    let submit: (String) async -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                TextField(String(localized: "residentInput.placeholder"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit(submitIfPossible)
                    .disabled(isInputDisabled)

                Button(String(localized: "residentInput.send"), action: submitIfPossible)
                    .disabled(!canSubmit)
            }

            if let errorKey = state.errorKey {
                Text(String(localized: String.LocalizationValue(errorKey)))
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isInputDisabled: Bool {
        state.isSubmitting || !isResidentAvailable
    }

    private var canSubmit: Bool {
        !trimmedText.isEmpty && !isInputDisabled
    }

    private func submitIfPossible() {
        guard canSubmit else { return }
        let submittedText = text
        Task { @MainActor in
            if await submit(submittedText) {
                text = ""
            }
        }
    }
}

#if DEBUG
private struct ParticleOrientationDebugOverlay: View {
    @ObservedObject var state: ParticleOrientationOverlayState

    var body: some View {
        Canvas { canvas, size in
            drawClockLabels(in: &canvas, size: size)
            drawAxisSet(
                in: &canvas,
                origin: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                length: 78,
                lineWidth: 2
            )
            drawAxisSet(
                in: &canvas,
                origin: CGPoint(x: 82, y: size.height - 92),
                length: 42,
                lineWidth: 1.7
            )
        }
    }

    private func drawAxisSet(
        in canvas: inout GraphicsContext,
        origin: CGPoint,
        length: CGFloat,
        lineWidth: CGFloat
    ) {
        let axes: [(String, SIMD3<Double>, Color)] = [
            ("X", SIMD3<Double>(1, 0, 0), .red),
            ("Y", SIMD3<Double>(0, 1, 0), .green),
            ("Z", SIMD3<Double>(0, 0, 1), .blue)
        ]

        for axis in axes {
            let endpoint = projectedAxisPoint(
                axis.1 * -0.42,
                origin: origin,
                length: length
            )
            var path = Path()
            path.move(to: origin)
            path.addLine(to: endpoint.point)
            canvas.stroke(path, with: .color(axis.2.opacity(0.20)), lineWidth: max(1, lineWidth * 0.72))
        }

        for axis in axes {
            let endpoint = projectedAxisPoint(
                axis.1,
                origin: origin,
                length: length
            )
            var path = Path()
            path.move(to: origin)
            path.addLine(to: endpoint.point)
            canvas.stroke(path, with: .color(axis.2.opacity(endpoint.opacity)), lineWidth: lineWidth * endpoint.scale)
            canvas.fill(
                Path(ellipseIn: CGRect(
                    x: endpoint.point.x - 3 * endpoint.scale,
                    y: endpoint.point.y - 3 * endpoint.scale,
                    width: 6 * endpoint.scale,
                    height: 6 * endpoint.scale
                )),
                with: .color(axis.2.opacity(min(0.96, endpoint.opacity + 0.08)))
            )
            canvas.draw(
                Text(axis.0)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(axis.2.opacity(min(0.98, endpoint.opacity + 0.12))),
                at: CGPoint(x: endpoint.point.x + 10, y: endpoint.point.y)
            )
        }
    }

    private func projectedAxisPoint(
        _ vector: SIMD3<Double>,
        origin: CGPoint,
        length: CGFloat
    ) -> (point: CGPoint, scale: CGFloat, opacity: Double) {
        let viewed = rotate(vector)
        let bodyPerspective = max(0.84, min(1.20, 1.0 / (1.0 - viewed.z * 0.30)))
        let depth = 3.2 - viewed.z
        let depthPerspective = 2.8 / max(1.4, depth)
        let scale = CGFloat(max(0.64, min(1.20, depthPerspective * 0.98)))
        let opacity = max(0.34, min(0.90, 0.62 + viewed.z * 0.16))
        return (
            CGPoint(
                x: origin.x + CGFloat(viewed.x * bodyPerspective) * length * scale,
                y: origin.y - CGFloat(viewed.y * bodyPerspective) * length * scale
            ),
            scale,
            opacity
        )
    }

    private func rotate(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        let rawQuaternion = state.orientation.quaternion
        let quaternionVector = SIMD3<Double>(
            Double(rawQuaternion.x),
            Double(rawQuaternion.y),
            Double(rawQuaternion.z)
        )
        let quaternionReal = Double(rawQuaternion.w)
        return vector + 2 * simd_cross(
            quaternionVector,
            simd_cross(quaternionVector, vector) + quaternionReal * vector
        )
    }

    private func drawClockLabels(in canvas: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let radiusX = max(120, size.width * 0.5 - 34)
        let radiusY = max(120, size.height * 0.5 - 48)

        for hour in 1...12 {
            let angle = Double(hour % 12) / 12.0 * 2.0 * Double.pi - Double.pi / 2.0
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radiusX,
                y: center.y + CGFloat(sin(angle)) * radiusY
            )
            drawAxisLabel("\(hour)", at: point, in: &canvas)
        }
    }

    private func drawAxisLabel(
        _ value: String,
        at point: CGPoint,
        in canvas: inout GraphicsContext
    ) {
        canvas.draw(
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(
                    .white.opacity(
                        ParticleTuning.Engine.orientationGuideLabelOpacity
                    )
                ),
            at: point
        )
    }
}

private enum ParticleDebugSection {
    case diagnostics
    case provider
    case shell
    case renderAdapter
    case particle
    case color
}

struct ParticleDebugWindow: View {
    static let sceneID = "particle-debug-window"

    @ObservedObject var controller: AppController
    @ObservedObject var presentationSettings: ParticlePresentationSettings

    var body: some View {
        ParticleDebugPanel(
            snapshot: controller.particleDebugSnapshot,
            providerState: controller.providerDebugState,
            dialogueAuditState: controller.dialogueAuditState,
            runtimeOrchestrationState: controller.runtimeOrchestrationState,
            shellMode: controller.particleShellMode,
            renderKind: controller.particleRenderKind,
            tuning: $presentationSettings.tuning,
            colorProfile: $presentationSettings.colorProfile,
            orientationOverlayVisible: $presentationSettings.isOrientationOverlayVisible,
            manualRotationEnabled: $presentationSettings.isManualRotationEnabled,
            defaultColorProfile: controller.particleColorProfile,
            setShellMode: controller.setParticleShellMode,
            setRenderKind: controller.setParticleRenderKind,
            rebuildFixedSeed: presentationSettings.rebuildWithFixedSeed,
            resetRotation: presentationSettings.resetViewOrientation,
            debugVisualIntent: presentationSettings.debugVisualIntent,
            isDebugAutoCycleEnabled: presentationSettings.isDebugAutoCycleEnabled,
            selectDebugVisualIntent: presentationSettings.selectDebugVisualIntent,
            setDebugAutoCycleEnabled: presentationSettings.setDebugAutoCycleEnabled,
            followRuntimeVisualIntent: presentationSettings.followRuntimeVisualIntent,
            runDebugTransitionStressTest: presentationSettings.runDebugTransitionStressTest,
            shapeTarget: presentationSettings.shapeTarget,
            selectDebugShapeTarget: presentationSettings.selectDebugShapeTarget,
            debugSpeechSignal: presentationSettings.debugSpeechSignal,
            debugSpeechIntensity: presentationSettings.debugSpeechIntensity,
            simulateDebugSpeech: presentationSettings.simulateDebugSpeech,
            setDebugSpeechIntensity: presentationSettings.setDebugSpeechIntensity,
            followRuntimeSpeech: presentationSettings.followRuntimeSpeech,
            refreshColorProfileSnapshot: {
                controller.updateEffectiveParticleColorProfile(
                    presentationSettings.colorProfile,
                    savedOverride: ParticleColorProfile.hasSavedProfile()
                )
            },
            importDR: openDebugDRImportPanel,
            saveProviderConfiguration: controller.saveProviderConfiguration,
            saveProviderCredential: controller.saveProviderCredential,
            deleteProviderCredential: controller.deleteProviderCredential,
            testResidentReply: controller.testResidentReply,
            copyDialogueAudit: controller.copyDialogueAudit,
            exportDialogueAudit: controller.exportDialogueAudit,
            clearDialogueAudit: controller.clearDialogueAudit,
            clearDialogueTestData: controller.clearDialogueTestData,
            copyRuntimeOrchestration: controller.copyRuntimeOrchestrationInteraction,
            exportRuntimeOrchestration: controller.exportRuntimeOrchestrationInteraction,
            clearRuntimeOrchestration: controller.clearRuntimeOrchestrationRecords
        )
        .onAppear {
            controller.setParticleDebugPanelPresented(true)
        }
        .onDisappear {
            controller.setParticleDebugPanelPresented(false)
        }
    }

    private func openDebugDRImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        var contentTypes: [UTType] = [.json]
        if let digitalResidentType = UTType(filenameExtension: "digital_resident") {
            contentTypes.append(digitalResidentType)
        }
        if let drType = UTType(filenameExtension: "dr") {
            contentTypes.append(drType)
        }
        panel.allowedContentTypes = contentTypes

        if panel.runModal() == .OK, let url = panel.url {
            controller.debugImportResident(from: url)
            presentationSettings.colorProfile = controller.particleColorProfile
        }
    }
}

private enum ParticleTuningGroup: String, CaseIterable, Identifiable {
    case basics
    case shape
    case motion
    case surface
    case scatter

    var id: String { rawValue }

    var localizedKey: String {
        "particleDebug.tuningGroup.\(rawValue)"
    }

    var parameters: [ParticleTuningParameter] {
        switch self {
        case .basics:
            return [
                .sphereRadius,
                .globalScale,
                .pointSizeScale,
                .brightness,
                .alphaScale
            ]
        case .shape:
            return [
                .shapeStrength,
                .shapeFeatureScale,
                .shapeSmoothness,
                .shapeSeed
            ]
        case .motion:
            return [
                .breathingAmount,
                .breathingSpeed,
                .flowStrength,
                .flowShapeStrength,
                .flowSpeed,
                .flowDirection,
                .flowSeed,
                .flowBrightnessStrength,
                .rotationSpeed,
                .rotationDirection,
                .disturbanceStrength,
                .aggregationStrength,
                .damping
            ]
        case .surface:
            return [
                .surfaceRatio,
                .surfaceLightStrength,
                .ridgeStrength,
                .ridgeWidth,
                .ridgeBreakup,
                .ridgeSeed,
                .ridgeFlowBinding,
                .edgeDustAmount,
                .edgeFrayAmount
            ]
        case .scatter:
            return [
                .scatterStrength,
                .scatterClusterStrength,
                .scatterClusterScale,
                .scatterSeed
            ]
        }
    }
}

private struct ParticleDebugPanel: View {
    let snapshot: ParticleDebugSnapshot
    let providerState: ProviderDebugViewState
    let dialogueAuditState: DialogueAuditViewState
    let runtimeOrchestrationState: RuntimeOrchestrationViewState
    let shellMode: ParticleShellMode
    let renderKind: ParticleRenderKind
    @Binding var tuning: ParticleTuning
    @Binding var colorProfile: ParticleColorProfile
    @Binding var orientationOverlayVisible: Bool
    @Binding var manualRotationEnabled: Bool
    let defaultColorProfile: ParticleColorProfile
    let setShellMode: (ParticleShellMode) -> Void
    let setRenderKind: (ParticleRenderKind) -> Void
    let rebuildFixedSeed: () -> Void
    let resetRotation: () -> Void
    let debugVisualIntent: ResidentVisualIntent?
    let isDebugAutoCycleEnabled: Bool
    let selectDebugVisualIntent: (ResidentVisualIntent) -> Void
    let setDebugAutoCycleEnabled: (Bool) -> Void
    let followRuntimeVisualIntent: () -> Void
    let runDebugTransitionStressTest: () -> Void
    let shapeTarget: ParticleShapeTarget
    let selectDebugShapeTarget: (ParticleShapeTarget) -> Void
    let debugSpeechSignal: ResidentSpeechSignal?
    let debugSpeechIntensity: Double
    let simulateDebugSpeech: (ResidentSpeechPhase) -> Void
    let setDebugSpeechIntensity: (Double) -> Void
    let followRuntimeSpeech: () -> Void
    let refreshColorProfileSnapshot: () -> Void
    let importDR: () -> Void
    let saveProviderConfiguration: (ProviderProfile) -> Void
    let saveProviderCredential: (String) -> Void
    let deleteProviderCredential: () -> Void
    let testResidentReply: (String) async -> Void
    let copyDialogueAudit: () -> Void
    let exportDialogueAudit: () -> Void
    let clearDialogueAudit: () -> Void
    let clearDialogueTestData: () -> Void
    let copyRuntimeOrchestration: (UUID) -> Void
    let exportRuntimeOrchestration: (UUID) -> Void
    let clearRuntimeOrchestration: () -> Void
    @State private var section: ParticleDebugSection = .diagnostics
    @State private var tuningGroup: ParticleTuningGroup = .basics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "particleDebug.title"))
                    .font(.headline)
                Text(sectionSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(sectionCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: $section) {
                Text(String(localized: "particleDebug.diagnostics"))
                    .tag(ParticleDebugSection.diagnostics)
                Text(String(localized: "particleDebug.provider"))
                    .tag(ParticleDebugSection.provider)
                Text(String(localized: "particleDebug.shellMode"))
                    .tag(ParticleDebugSection.shell)
                Text(String(localized: "particleDebug.renderAdapter"))
                    .tag(ParticleDebugSection.renderAdapter)
                Text(String(localized: "particleDebug.particleAdjustment"))
                    .tag(ParticleDebugSection.particle)
                Text(String(localized: "particleDebug.colorAdjustment"))
                    .tag(ParticleDebugSection.color)
            }
            .pickerStyle(.segmented)

            if section == .particle {
                Picker("", selection: $tuningGroup) {
                    ForEach(ParticleTuningGroup.allCases) { group in
                        Text(
                            String(
                                localized: String.LocalizationValue(
                                    group.localizedKey
                                )
                            )
                        )
                        .tag(group)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle(String(localized: "particleDebug.orientation.overlay"), isOn: $orientationOverlayVisible)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)

            HStack {
                Toggle(
                    String(localized: "particleDebug.orientation.manualRotation"),
                    isOn: $manualRotationEnabled
                )
                .font(.system(size: 12))
                .toggleStyle(.checkbox)

                Spacer()

                Button(
                    String(localized: "particleDebug.orientation.resetRotation"),
                    action: resetRotation
                )
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "particleDebug.shapeTest"))
                    .font(.system(size: 12, weight: .medium))

                HStack(spacing: 5) {
                    ForEach(
                        ParticleShapeTarget.allCases.filter(\.isImplemented)
                    ) { target in
                        Button(
                            NSLocalizedString(
                                target.debugLocalizedKey,
                                comment: ""
                            )
                        ) {
                            selectDebugShapeTarget(target)
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .disabled(shapeTarget == target)
                    }
                }

                Divider()

                Text(String(localized: "particleDebug.transitionTest"))
                    .font(.system(size: 12, weight: .medium))

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 70), spacing: 5)
                    ],
                    spacing: 5
                ) {
                    ForEach(ResidentVisualIntent.allCases) { intent in
                        Button(NSLocalizedString(intent.debugLocalizedKey, comment: "")) {
                            selectDebugVisualIntent(intent)
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .disabled(debugVisualIntent == intent)
                    }
                }

                HStack {
                    Toggle(
                        String(localized: "particleDebug.transition.autoCycle"),
                        isOn: Binding(
                            get: { isDebugAutoCycleEnabled },
                            set: setDebugAutoCycleEnabled
                        )
                    )
                    .toggleStyle(.checkbox)

                    Spacer()

                    Button(
                        String(localized: "particleDebug.transition.followRuntime"),
                        action: followRuntimeVisualIntent
                    )
                    Button(
                        String(localized: "particleDebug.transition.stress100"),
                        action: runDebugTransitionStressTest
                    )
                }
                .controlSize(.small)

                Divider()

                Text(String(localized: "particleDebug.speechTest"))
                    .font(.system(size: 12, weight: .medium))

                HStack(spacing: 5) {
                    ForEach(
                        [
                            ResidentSpeechPhase.started,
                            .sustained,
                            .paused,
                            .ended
                        ]
                    ) { phase in
                        Button(NSLocalizedString(phase.debugLocalizedKey, comment: "")) {
                            simulateDebugSpeech(phase)
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .disabled(debugSpeechSignal?.phase == phase)
                    }

                    Spacer()

                    Button(
                        String(localized: "particleDebug.speech.followRuntime"),
                        action: followRuntimeSpeech
                    )
                    .controlSize(.small)
                }

                HStack {
                    Text(String(localized: "particleDebug.speech.intensity"))
                        .font(.system(size: 11))
                    Slider(
                        value: Binding(
                            get: { debugSpeechIntensity },
                            set: setDebugSpeechIntensity
                        ),
                        in: 0...1
                    )
                    Text(String(format: "%.2f", debugSpeechIntensity))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 34, alignment: .trailing)
                }
            }

            if section == .color {
                Button {
                    importDR()
                } label: {
                    Label(String(localized: "particleDebug.importDR"), systemImage: "doc.badge.plus")
                }
                .controlSize(.small)
            }

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    switch section {
                    case .diagnostics:
                        ParticleDiagnosticsView(snapshot: snapshot)
                    case .provider:
                        VStack(spacing: 14) {
                            TextProviderDebugView(
                                state: providerState,
                                saveConfiguration: saveProviderConfiguration,
                                saveCredential: saveProviderCredential,
                                deleteCredential: deleteProviderCredential,
                                testReply: testResidentReply
                            )
                            DialogueAuditDebugView(
                                state: dialogueAuditState,
                                copyAll: copyDialogueAudit,
                                exportText: exportDialogueAudit,
                                clear: clearDialogueAudit,
                                clearTestData: clearDialogueTestData
                            )
                            RuntimeOrchestrationDebugView(
                                state: runtimeOrchestrationState,
                                copyInteraction: copyRuntimeOrchestration,
                                exportInteraction: exportRuntimeOrchestration,
                                clear: clearRuntimeOrchestration
                            )
                        }
                    case .shell:
                        ParticleShellModeView(
                            snapshot: snapshot,
                            shellMode: shellMode,
                            setShellMode: setShellMode
                        )
                    case .renderAdapter:
                        ParticleRenderAdapterView(
                            snapshot: snapshot,
                            renderKind: renderKind,
                            setRenderKind: setRenderKind
                        )
                    case .particle:
                        ForEach(tuningGroup.parameters) { parameter in
                            if parameter == .flowDirection {
                                ParticleDirectionRow(
                                    parameter: parameter,
                                    tuning: $tuning
                                )
                            } else if parameter == .rotationDirection {
                                ParticleSpinDirectionRow(tuning: $tuning)
                            } else {
                                ParticleParameterRow(
                                    parameter: parameter,
                                    tuning: $tuning
                                )
                            }
                        }
                    case .color:
                        ForEach(ParticleColorParameter.allCases) { parameter in
                            ParticleColorParameterRow(parameter: parameter, colorProfile: $colorProfile)
                        }
                    }
                }
            }
            .frame(minHeight: 280, maxHeight: .infinity)

            if section == .particle || section == .color {
                Divider()

                HStack {
                    Button(String(localized: "particleDebug.restoreDefault")) {
                        restoreDefault()
                    }

                    if section == .particle {
                        Button(String(localized: "particleDebug.rebuildFixedSeed")) {
                            rebuildFixedSeed()
                        }
                    }

                    Spacer()

                    Button(String(localized: "particleDebug.save")) {
                        saveCurrentSection()
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                }
            }
        }
        .padding(14)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 500, idealHeight: 620)
    }

    private var sectionSubtitle: String {
        switch section {
        case .diagnostics:
            return String(localized: "particleDebug.diagnostics")
        case .provider:
            return String(localized: "particleDebug.provider")
        case .shell:
            return String(localized: "particleDebug.shellMode")
        case .renderAdapter:
            return String(localized: "particleDebug.renderAdapter")
        case .particle:
            return String(localized: "particleDebug.particleAdjustment")
        case .color:
            return String(localized: "particleDebug.colorAdjustment")
        }
    }

    private var sectionCaption: String {
        switch section {
        case .diagnostics:
            return String(localized: "particleDebug.diagnosticsCaption")
        case .provider:
            return String(localized: "particleDebug.providerCaption")
        case .shell:
            return String(localized: "particleDebug.shellModeCaption")
        case .renderAdapter:
            return String(localized: "particleDebug.renderAdapterCaption")
        case .particle:
            return String(localized: "particleDebug.parameters")
        case .color:
            return String(localized: "particleDebug.colorParameters")
        }
    }

    private func restoreDefault() {
        switch section {
        case .diagnostics:
            break
        case .provider:
            break
        case .shell:
            break
        case .renderAdapter:
            break
        case .particle:
            tuning = .systemDefault
            ParticleTuning.clearSaved()
        case .color:
            colorProfile = defaultColorProfile
            ParticleColorProfile.clearSaved()
            refreshColorProfileSnapshot()
        }
    }

    private func saveCurrentSection() {
        switch section {
        case .diagnostics:
            break
        case .provider:
            break
        case .shell:
            break
        case .renderAdapter:
            break
        case .particle:
            tuning.save()
        case .color:
            colorProfile.save()
            refreshColorProfileSnapshot()
        }
    }
}

private struct DebugCollapsibleMenu<Content: View>: View {
    let titleKey: String
    @Binding var isExpanded: Bool
    private let content: Content

    init(
        titleKey: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(String(localized: String.LocalizationValue(titleKey)))
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(isExpanded ? 0.16 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )

            if isExpanded {
                content
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
            }
        }
    }
}

private struct DialogueAuditDebugView: View {
    let state: DialogueAuditViewState
    let copyAll: () -> Void
    let exportText: () -> Void
    let clear: () -> Void
    let clearTestData: () -> Void
    @State private var isExpanded = false
    @State private var isClearConfirmationPresented = false

    var body: some View {
        DebugCollapsibleMenu(
            titleKey: "dialogueAudit.menuTitle",
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(localized: "dialogueAudit.privacyNotice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if state.entries.isEmpty {
                    Text(String(localized: "dialogueAudit.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(state.entries) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.displayName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(entry.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }

                HStack {
                    Button(String(localized: "dialogueAudit.copyAll"), action: copyAll)
                    Button(String(localized: "dialogueAudit.export"), action: exportText)
                    Spacer()
                    Button(String(localized: "dialogueAudit.clear"), action: clear)
                }
                .disabled(state.entries.isEmpty)

                Button(role: .destructive) {
                    isClearConfirmationPresented = true
                } label: {
                    Text(String(localized: "dialogueAudit.clearTestData"))
                }

                if let statusKey = state.statusKey {
                    Text(String(localized: String.LocalizationValue(statusKey)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert(
            String(localized: "dialogueAudit.clearTestData.confirmTitle"),
            isPresented: $isClearConfirmationPresented
        ) {
            Button(String(localized: "dialogueAudit.clearTestData.cancel"), role: .cancel) {}
            Button(String(localized: "dialogueAudit.clearTestData.confirm"), role: .destructive) {
                clearTestData()
            }
        } message: {
            Text(String(localized: "dialogueAudit.clearTestData.message"))
        }
    }

    private var localizedCount: String {
        String(
            format: String(localized: "dialogueAudit.count"),
            locale: Locale.current,
            state.entries.count
        )
    }
}

private struct RuntimeOrchestrationDebugView: View {
    let state: RuntimeOrchestrationViewState
    let copyInteraction: (UUID) -> Void
    let exportInteraction: (UUID) -> Void
    let clear: () -> Void
    @State private var isExpanded = false

    var body: some View {
        DebugCollapsibleMenu(
            titleKey: "runtimeOrchestration.title",
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "runtimeOrchestration.privacyNotice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if state.interactions.isEmpty {
                    Text(String(localized: "runtimeOrchestration.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(state.interactions.reversed())) { interaction in
                            interactionView(interaction)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(String(localized: "runtimeOrchestration.clear"), action: clear)
                        .disabled(state.interactions.isEmpty)
                }

                if let statusKey = state.statusKey {
                    Text(String(localized: String.LocalizationValue(statusKey)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func interactionView(
        _ interaction: RuntimeOrchestrationInteractionViewState
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                detailRow("runtimeOrchestration.field.interactionID", interaction.id.uuidString)
                detailRow("runtimeOrchestration.field.residentID", interaction.residentID)
                detailRow("runtimeOrchestration.field.sessionID", interaction.sessionID)
                detailRow(
                    "runtimeOrchestration.field.startedAt",
                    interaction.startedAt.formatted(date: .abbreviated, time: .standard)
                )
                detailRow(
                    "runtimeOrchestration.field.endedAt",
                    interaction.endedAt.formatted(date: .abbreviated, time: .standard)
                )
                detailRow(
                    "runtimeOrchestration.field.duration",
                    localizedMilliseconds(interaction.durationMilliseconds)
                )
                detailRow(
                    "runtimeOrchestration.field.dailyRules",
                    localizedValue("boolean", interaction.dailyRulesEnabled ? "enabled" : "disabled")
                )
                detailRow(
                    "runtimeOrchestration.field.emotionalRules",
                    localizedValue(
                        "boolean",
                        interaction.emotionalRulesEnabled ? "enabled" : "disabled"
                    )
                )
                detailRow(
                    "runtimeOrchestration.field.recentMessages",
                    String(interaction.recentMessageCount)
                )
                detailRow(
                    "runtimeOrchestration.field.fewShotCount",
                    String(interaction.fewShotReferences.count)
                )
                ForEach(interaction.fewShotReferences) { reference in
                    detailRow(
                        "runtimeOrchestration.field.fewShot",
                        "\(reference.exampleID) · \(localizedValue("fewShotKind", reference.kind))"
                    )
                }
                detailRow(
                    "runtimeOrchestration.field.preferenceCount",
                    String(interaction.approvedPreferenceCount)
                )
                detailRow(
                    "runtimeOrchestration.field.provider",
                    interaction.providerID ?? String(localized: "runtimeOrchestration.unavailable")
                )
                detailRow(
                    "runtimeOrchestration.field.model",
                    interaction.modelID ?? String(localized: "runtimeOrchestration.unavailable")
                )
                detailRow(
                    "runtimeOrchestration.field.adapter",
                    interaction.adapterType ?? String(localized: "runtimeOrchestration.unavailable")
                )
                detailRow(
                    "runtimeOrchestration.field.result",
                    localizedValue("result", interaction.result)
                )
                detailRow(
                    "runtimeOrchestration.field.error",
                    interaction.errorCategory.map { localizedValue("error", $0) }
                        ?? String(localized: "runtimeOrchestration.none")
                )
                detailRow(
                    "runtimeOrchestration.field.sessionWrite",
                    localizedValue("sessionWrite", interaction.sessionWriteStatus)
                )
                detailRow(
                    "runtimeOrchestration.field.subtitle",
                    localizedValue("presentation", interaction.subtitleState)
                )
                detailRow(
                    "runtimeOrchestration.field.particle",
                    localizedValue("presentation", interaction.particleState)
                )

                Divider()
                Text(String(localized: "runtimeOrchestration.timeline"))
                    .font(.caption.weight(.semibold))
                ForEach(interaction.steps) { step in
                    HStack(alignment: .firstTextBaseline) {
                        Text(localizedValue("step", step.kind))
                        Spacer(minLength: 8)
                        Text(localizedValue("status", step.status))
                            .foregroundStyle(.secondary)
                        Text(localizedMilliseconds(step.durationMilliseconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                HStack {
                    Button(String(localized: "runtimeOrchestration.copy")) {
                        copyInteraction(interaction.id)
                    }
                    Button(String(localized: "runtimeOrchestration.export")) {
                        exportInteraction(interaction.id)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(String(interaction.id.uuidString.prefix(8)))
                    .monospaced()
                Spacer()
                Text(localizedValue("result", interaction.result))
                    .foregroundStyle(.secondary)
                Text(localizedMilliseconds(interaction.durationMilliseconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: String.LocalizationValue(key)))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func localizedValue(_ namespace: String, _ value: String) -> String {
        let key = "runtimeOrchestration.\(namespace).\(value)"
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private func localizedMilliseconds(_ value: Int) -> String {
        String(
            format: String(localized: "runtimeOrchestration.milliseconds"),
            locale: Locale.current,
            value
        )
    }

    private var localizedCount: String {
        String(
            format: String(localized: "runtimeOrchestration.count"),
            locale: Locale.current,
            state.interactions.count
        )
    }
}

private struct TextProviderDebugView: View {
    let state: ProviderDebugViewState
    let saveConfiguration: (ProviderProfile) -> Void
    let saveCredential: (String) -> Void
    let deleteCredential: () -> Void
    let testReply: (String) async -> Void

    @State private var profile: ProviderProfile
    @State private var credentialInput = ""
    @State private var testInput = ""
    @State private var isConfigurationExpanded = true
    @State private var isTestExpanded = false

    init(
        state: ProviderDebugViewState,
        saveConfiguration: @escaping (ProviderProfile) -> Void,
        saveCredential: @escaping (String) -> Void,
        deleteCredential: @escaping () -> Void,
        testReply: @escaping (String) async -> Void
    ) {
        self.state = state
        self.saveConfiguration = saveConfiguration
        self.saveCredential = saveCredential
        self.deleteCredential = deleteCredential
        self.testReply = testReply
        _profile = State(initialValue: state.profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DebugCollapsibleMenu(
                titleKey: "particleDebug.provider.apiConfiguration",
                isExpanded: $isConfigurationExpanded
            ) {
                configurationContent
            }

            DebugCollapsibleMenu(
                titleKey: "particleDebug.provider.dialogueTest",
                isExpanded: $isTestExpanded
            ) {
                dialogueTestContent
            }
        }
    }

    private var configurationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(String(localized: "particleDebug.provider.configuration")) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(String(localized: "particleDebug.provider.providerID"), text: $profile.providerID)
                    TextField(String(localized: "particleDebug.provider.modelID"), text: $profile.modelID)
                    TextField(String(localized: "particleDebug.provider.baseURL"), text: $profile.baseURL)
                    Toggle(String(localized: "particleDebug.provider.enabled"), isOn: $profile.enabled)

                    ParticleDiagnosticsRow(
                        labelKey: "particleDebug.provider.adapterType",
                        value: profile.adapterType
                    )
                    ParticleDiagnosticsRow(
                        labelKey: "particleDebug.provider.timeout",
                        value: "\(Int(profile.timeout))s"
                    )
                    ParticleDiagnosticsRow(
                        labelKey: "particleDebug.provider.stream",
                        value: profile.stream ? "true" : "false"
                    )
                    ParticleDiagnosticsRow(
                        labelKey: "particleDebug.provider.thinkingMode",
                        value: profile.thinkingMode
                    )

                    HStack {
                        Text(configurationStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "particleDebug.provider.saveConfiguration")) {
                            saveConfiguration(profile)
                        }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox(String(localized: "particleDebug.provider.credential")) {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField(
                        String(localized: "particleDebug.provider.credentialPlaceholder"),
                        text: $credentialInput
                    )
                    HStack {
                        Text(credentialStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "particleDebug.provider.deleteCredential")) {
                            credentialInput = ""
                            deleteCredential()
                        }
                        Button(String(localized: "particleDebug.provider.saveCredential")) {
                            let value = credentialInput
                            credentialInput = ""
                            saveCredential(value)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var dialogueTestContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(String(localized: "particleDebug.provider.test")) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(
                        String(localized: "particleDebug.provider.testPlaceholder"),
                        text: $testInput
                    )
                    HStack {
                        Text(String(localized: String.LocalizationValue(state.statusKey)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if state.isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button(String(localized: "particleDebug.provider.testReply")) {
                            let input = testInput
                            Task {
                                await testReply(input)
                            }
                        }
                        .disabled(state.isTesting)
                    }
                    if !state.replyText.isEmpty {
                        Text(state.replyText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var configurationStatus: String {
        let isSaved = state.configurationSaved && profile == state.profile
        return String(localized: isSaved
            ? "particleDebug.provider.status.saved"
            : "particleDebug.provider.status.notSaved")
    }

    private var credentialStatus: String {
        String(localized: state.credentialSaved
            ? "particleDebug.provider.status.credentialPresent"
            : "particleDebug.provider.status.credentialMissing")
    }
}

private struct ParticleDiagnosticsView: View {
    let snapshot: ParticleDebugSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.render") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.fps", value: String(format: "%.1f", snapshot.fps))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.particleCount", value: "\(snapshot.particleCount)")
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.drawableSize", value: snapshot.drawableSize)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.preferredFPS", value: "\(snapshot.preferredFramesPerSecond)")
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.visualState") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.currentVisualState", value: snapshot.currentVisualState)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.targetVisualState", value: snapshot.targetVisualState)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.frameDeltaTime", value: String(format: "%.4fs", snapshot.frameDeltaTime))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.stateElapsedTime", value: String(format: "%.2fs", snapshot.stateElapsedTime))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.transitionDuration", value: String(format: "%.2fs", snapshot.transitionDuration))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.transitionProgress", value: String(format: "%.3f", snapshot.transitionProgress))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.speechPhase", value: snapshot.speechPhase)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.speechIntensity", value: String(format: "%.2f", snapshot.speechIntensity))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.lastTransitionReason", value: snapshot.lastTransitionReason)
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.shape") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.currentShape", value: snapshot.currentShape)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.targetShape", value: snapshot.targetShape)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.morphElapsedTime", value: String(format: "%.2fs", snapshot.morphElapsedTime))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.morphDuration", value: String(format: "%.2fs", snapshot.morphDuration))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.morphProgress", value: String(format: "%.3f", snapshot.morphProgress))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.lastMorphReason", value: snapshot.lastMorphReason)
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.avatarMapping") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.sourceAvatarState", value: snapshot.sourceAvatarState)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.mappedParticleState", value: snapshot.mappedParticleState)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.isDebugOverrideActive", value: boolText(snapshot.isDebugOverrideActive))
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.avatarMode") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.currentAvatarMode", value: snapshot.avatarMode)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.particleCoreMode", value: snapshot.particleCoreModeStatus)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.abstractBustMode", value: snapshot.abstractBustModeStatus)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.renderFallback", value: snapshot.renderFallback)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.renderFallbackReason", value: snapshot.renderFallbackReason)
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.renderAdapter") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.requestedRenderKind", value: snapshot.requestedRenderKind)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.activeRenderer", value: snapshot.activeRenderer)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.fallbackRenderer", value: snapshot.fallbackRenderer)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.fallbackReason", value: snapshot.fallbackReason)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.supportedRenderers", value: snapshot.supportedRenderers)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.reservedRenderers", value: snapshot.reservedRenderers)
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.shellMode") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.requestedShellMode", value: snapshot.requestedShellMode)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.activeShellMode", value: snapshot.activeShellMode)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.shellFallbackReason", value: snapshot.shellFallbackReason)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.darkShell", value: snapshot.darkShellStatus)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.immersiveShell", value: snapshot.immersiveShellStatus)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.transparentShell", value: snapshot.transparentShellStatus)
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.colorProfile") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.colorProfileSource", value: snapshot.colorProfileSource)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.baseColor", value: snapshot.baseColor)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.ridgeColor", value: snapshot.ridgeColor)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.highlightColor", value: snapshot.highlightColor)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.fallbackUsed", value: boolText(snapshot.fallbackUsed))
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.subtitleState") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.subtitlePhase", value: snapshot.subtitlePhase)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.hasSubtitleText", value: boolText(snapshot.hasSubtitleText))
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.interaction") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.mouseInfluenceEnabled", value: boolText(snapshot.mouseInfluenceEnabled))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.mouseInsideParticleArea", value: boolText(snapshot.mouseInsideParticleArea))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.interactionStrength", value: String(format: "%.2f", snapshot.interactionStrength))
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.boundaryStatus") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.runtimeCoreModified", value: boolText(snapshot.runtimeCoreModified))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.runtimeAPIModified", value: boolText(snapshot.runtimeAPIModified))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.drSchemaModified", value: boolText(snapshot.drSchemaModified))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.providerTTSConnected", value: boolText(snapshot.providerTTSConnected))
            }
        }
    }

    private func boolText(_ value: Bool) -> String {
        value ? String(localized: "particleDebug.value.true") : String(localized: "particleDebug.value.false")
    }
}

private struct ParticleShellModeView: View {
    let snapshot: ParticleDebugSnapshot
    let shellMode: ParticleShellMode
    let setShellMode: (ParticleShellMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "particleDebug.diagnostics.requestedShellMode"), selection: shellBinding) {
                Text(String(localized: "particleDebug.shellMode.darkShell"))
                    .tag(ParticleShellMode.darkShell)
                Text(String(localized: "particleDebug.shellMode.immersiveShell"))
                    .tag(ParticleShellMode.immersiveShell)
                Text(String(localized: "particleDebug.shellMode.transparentShell"))
                    .tag(ParticleShellMode.transparentShell)
            }
            .pickerStyle(.menu)

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.shellMode") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.requestedShellMode", value: snapshot.requestedShellMode)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.activeShellMode", value: snapshot.activeShellMode)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.shellFallbackReason", value: snapshot.shellFallbackReason)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.darkShell", value: snapshot.darkShellStatus)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.immersiveShell", value: snapshot.immersiveShellStatus)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.transparentShell", value: snapshot.transparentShellStatus)
            }
        }
    }

    private var shellBinding: Binding<ParticleShellMode> {
        Binding {
            shellMode
        } set: { newValue in
            setShellMode(newValue)
        }
    }
}

private struct ParticleRenderAdapterView: View {
    let snapshot: ParticleDebugSnapshot
    let renderKind: ParticleRenderKind
    let setRenderKind: (ParticleRenderKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "particleDebug.diagnostics.requestedRenderKind"), selection: kindBinding) {
                ForEach(ParticleRenderKind.allCases) { kind in
                    Text(String(localized: String.LocalizationValue(kind.localizedKey)))
                        .tag(kind)
                }
            }
            .pickerStyle(.menu)

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.renderAdapter") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.requestedRenderKind", value: snapshot.requestedRenderKind)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.activeRenderer", value: snapshot.activeRenderer)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.fallbackRenderer", value: snapshot.fallbackRenderer)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.fallbackReason", value: snapshot.fallbackReason)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.supportedRenderers", value: snapshot.supportedRenderers)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.reservedRenderers", value: snapshot.reservedRenderers)
            }

            ParticleDiagnosticsSection(titleKey: "particleDebug.diagnostics.avatarMode") {
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.currentAvatarMode", value: snapshot.avatarMode)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.particleCoreMode", value: snapshot.particleCoreModeStatus)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.abstractBustMode", value: snapshot.abstractBustModeStatus)
            }
        }
    }

    private var kindBinding: Binding<ParticleRenderKind> {
        Binding {
            renderKind
        } set: { newValue in
            setRenderKind(newValue)
        }
    }
}

private struct ParticleDiagnosticsSection<Content: View>: View {
    let titleKey: String
    let content: () -> Content

    init(titleKey: String, @ViewBuilder content: @escaping () -> Content) {
        self.titleKey = titleKey
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(localized: String.LocalizationValue(titleKey)))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct ParticleDiagnosticsRow: View {
    let labelKey: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(localized: String.LocalizationValue(labelKey)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 156, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.86))
                .lineLimit(2)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
    }
}

private struct ParticleParameterRow: View {
    let parameter: ParticleTuningParameter
    @Binding var tuning: ParticleTuning

    var body: some View {
        HStack(spacing: 10) {
            Text(String(localized: String.LocalizationValue(parameter.localizedKey)))
                .font(.system(size: 12))
                .frame(width: 116, alignment: .leading)

            Slider(value: value, in: 0...1)

            TextField("", value: value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
        }
    }

    private var value: Binding<Double> {
        Binding {
            tuning[keyPath: parameter.keyPath]
        } set: { newValue in
            tuning[keyPath: parameter.keyPath] = min(1, max(0, newValue))
        }
    }
}

private struct ParticleDirectionRow: View {
    let parameter: ParticleTuningParameter
    @Binding var tuning: ParticleTuning

    var body: some View {
        HStack(spacing: 10) {
            Text(String(localized: String.LocalizationValue(parameter.localizedKey)))
                .font(.system(size: 12))
                .frame(width: 116, alignment: .leading)

            Picker("", selection: direction) {
                ForEach(ParticleFlowDirection.allCases) { direction in
                    Text(
                        String(
                            localized: String.LocalizationValue(
                                direction.localizedKey
                            )
                        )
                    )
                    .tag(direction)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var direction: Binding<ParticleFlowDirection> {
        Binding {
            ParticleFlowDirection.nearest(
                to: tuning[keyPath: parameter.keyPath]
            )
        } set: { newValue in
            tuning[keyPath: parameter.keyPath] = newValue.tuningValue
        }
    }
}

private struct ParticleSpinDirectionRow: View {
    @Binding var tuning: ParticleTuning

    var body: some View {
        HStack(spacing: 10) {
            Text(String(localized: "particleDebug.parameter.rotationDirection"))
                .font(.system(size: 12))
                .frame(width: 116, alignment: .leading)

            Picker("", selection: direction) {
                ForEach(ParticleSpinDirection.allCases) { direction in
                    Text(
                        String(
                            localized: String.LocalizationValue(
                                direction.localizedKey
                            )
                        )
                    )
                    .tag(direction)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var direction: Binding<ParticleSpinDirection> {
        Binding {
            ParticleSpinDirection.nearest(to: tuning.rotationDirection)
        } set: { newValue in
            tuning.rotationDirection = newValue.tuningValue
        }
    }
}

private struct ParticleColorParameterRow: View {
    let parameter: ParticleColorParameter
    @Binding var colorProfile: ParticleColorProfile

    var body: some View {
        HStack(spacing: 10) {
            Text(String(localized: String.LocalizationValue(parameter.localizedKey)))
                .font(.system(size: 12))
                .frame(width: 116, alignment: .leading)

            Slider(value: value, in: 0...1)

            TextField("", value: value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
        }
    }

    private var value: Binding<Double> {
        Binding {
            colorProfile[keyPath: parameter.keyPath]
        } set: { newValue in
            colorProfile[keyPath: parameter.keyPath] = min(1, max(0, newValue))
        }
    }
}
#endif

#Preview {
    ContentView(
        controller: AppController(),
        presentationSettings: ParticlePresentationSettings()
    )
}
