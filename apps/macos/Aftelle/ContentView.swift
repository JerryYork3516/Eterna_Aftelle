import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class ParticlePresentationSettings: ObservableObject {
    @Published var tuning = ParticleTuning.loadSaved()
    @Published var colorProfile = ParticleColorProfile.loadSaved() ?? .systemDefault
    @Published private(set) var rebuildGeneration = 0
    #if DEBUG
    @Published var isOrientationOverlayVisible = false
    #endif

    func rebuildWithFixedSeed() {
        rebuildGeneration &+= 1
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
    @State private var particleOrientationTimeSample = ParticleOrientationTimeSample.empty
    #endif

    var body: some View {
        ZStack {
            shellBackground
                .ignoresSafeArea()

            ParticleCoreMetalView(
                visualIntent: controller.residentVisualIntent,
                tuning: presentationSettings.tuning,
                colorProfile: presentationSettings.colorProfile,
                rebuildGeneration: presentationSettings.rebuildGeneration,
                isTransparentBackground: controller.particleShellMode == .transparentShell,
                debugMetricsHandler: { metrics in
                    controller.updateParticleRenderMetrics(metrics)
                    #if DEBUG
                    particleOrientationTimeSample = ParticleOrientationTimeSample(
                        renderElapsedTime: metrics.renderElapsedTime,
                        motionElapsedTime: metrics.motionElapsedTime,
                        sampleDate: Date()
                    )
                    #endif
                }
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
                ParticleOrientationDebugOverlay(tuning: presentationSettings.tuning, timeSample: particleOrientationTimeSample)
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
private struct ParticleOrientationTimeSample: Equatable {
    var renderElapsedTime: TimeInterval
    var motionElapsedTime: TimeInterval
    var sampleDate: Date

    static let empty = ParticleOrientationTimeSample(renderElapsedTime: 0, motionElapsedTime: 0, sampleDate: Date())

    func renderElapsed(at date: Date) -> TimeInterval {
        max(0, renderElapsedTime + date.timeIntervalSince(sampleDate))
    }

    func motionElapsed(at date: Date) -> TimeInterval {
        let currentRenderElapsed = renderElapsed(at: date)
        return motionElapsedTime + motionElapsedFormula(currentRenderElapsed) - motionElapsedFormula(renderElapsedTime)
    }

    private func motionElapsedFormula(_ renderElapsed: TimeInterval) -> TimeInterval {
        let speedPhaseRate: TimeInterval = 0.025
        return 0.42 * renderElapsed + (0.08 / speedPhaseRate) * (1 - cos(renderElapsed * speedPhaseRate))
    }
}

private struct ParticleOrientationDebugOverlay: View {
    let tuning: ParticleTuning
    let timeSample: ParticleOrientationTimeSample

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let motionTime = timeSample.motionElapsed(at: context.date)
                let renderElapsed = timeSample.renderElapsed(at: context.date)
                drawClockLabels(in: &canvas, size: size)
                drawMotionTimeline(in: &canvas, size: size, motionTime: motionTime, renderElapsed: renderElapsed)
                drawAxisSet(in: &canvas, origin: CGPoint(x: size.width * 0.5, y: size.height * 0.5), length: 78, motionTime: motionTime, lineWidth: 2.0)
                drawAxisSet(in: &canvas, origin: CGPoint(x: 82, y: size.height - 92), length: 42, motionTime: motionTime, lineWidth: 1.7)
            }
        }
    }

    private func rotationState(at motionTime: TimeInterval) -> ParticleRotationState {
        let tuneRotationSpeed = centeredControl(tuning.rotationSpeed, maximum: 2.40)
        let rotationTime = motionTime * 0.76 * tuneRotationSpeed
        let direction = ParticleSpinDirection.nearest(to: tuning.rotationDirection)
        let bodySpinAngle = rotationTime * direction.spinSign * 3.0
        return ParticleRotationState(
            rotationTime: rotationTime,
            bodySpinAngle: bodySpinAngle,
            angularVelocityPerMotionSecond: 0.76 * tuneRotationSpeed * direction.spinSign * 3.0,
            direction: direction
        )
    }

    private struct ParticleRotationState {
        let rotationTime: TimeInterval
        let bodySpinAngle: Double
        let angularVelocityPerMotionSecond: Double
        let direction: ParticleSpinDirection
    }

    private func drawAxisSet(in canvas: inout GraphicsContext, origin: CGPoint, length: CGFloat, motionTime: TimeInterval, lineWidth: CGFloat) {
        let rotationState = rotationState(at: motionTime)
        let axes: [(String, SIMD3<Double>, Color)] = [
            ("X", SIMD3<Double>(1, 0, 0), .red),
            ("Y", SIMD3<Double>(0, 1, 0), .green),
            ("Z", SIMD3<Double>(0, 0, 1), .blue)
        ]

        for axis in axes {
            let endpoint = projectedAxisPoint(axis.1 * -0.42, rotationState: rotationState, origin: origin, length: length)
            var path = Path()
            path.move(to: origin)
            path.addLine(to: endpoint.point)
            canvas.stroke(path, with: .color(axis.2.opacity(0.20)), lineWidth: max(1, lineWidth * 0.72))
        }

        for axis in axes {
            let endpoint = projectedAxisPoint(axis.1, rotationState: rotationState, origin: origin, length: length)
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

    private func projectedAxisPoint(_ vector: SIMD3<Double>, rotationState: ParticleRotationState, origin: CGPoint, length: CGFloat) -> (point: CGPoint, scale: CGFloat, opacity: Double) {
        let viewed = rotationState.direction.rotatesVertically
            ? rotateX(vector, rotationState.bodySpinAngle)
            : rotateY(vector, rotationState.bodySpinAngle)
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

    private func rotateX(_ vector: SIMD3<Double>, _ angle: Double) -> SIMD3<Double> {
        let c = cos(angle)
        let s = sin(angle)
        return SIMD3<Double>(
            vector.x,
            vector.y * c - vector.z * s,
            vector.y * s + vector.z * c
        )
    }

    private func rotateY(_ vector: SIMD3<Double>, _ angle: Double) -> SIMD3<Double> {
        let c = cos(angle)
        let s = sin(angle)
        return SIMD3<Double>(
            vector.x * c + vector.z * s,
            vector.y,
            -vector.x * s + vector.z * c
        )
    }


    private func centeredControl(_ value: Double, maximum: Double) -> Double {
        let control = min(1, max(0, value))
        if control <= 0.5 {
            return control * 2
        }
        return 1 + (control - 0.5) * 2 * (maximum - 1)
    }

    private func drawMotionTimeline(in canvas: inout GraphicsContext, size: CGSize, motionTime: TimeInterval, renderElapsed: TimeInterval) {
        let rotationState = rotationState(at: motionTime)
        let angularVelocity = rotationState.angularVelocityPerMotionSecond
        let realTimeAngularVelocity = abs(angularVelocity) * max(0.001, 0.42 + 0.08 * sin(renderElapsed * 0.025))
        let duration = (2.0 * Double.pi) / max(realTimeAngularVelocity, 0.001)
        let y = size.height - 52
        let start = CGPoint(x: 120, y: y)
        let end = CGPoint(x: max(180, size.width - 120), y: y)
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        canvas.stroke(path, with: .color(.white.opacity(0.32)), lineWidth: 1)

        for marker in rotationMarkers(direction: rotationState.direction) {
            let fraction = CGFloat(marker.degrees / 360.0)
            let x = start.x + (end.x - start.x) * fraction
            let markerTime = duration * marker.degrees / 360.0
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: y - marker.tickHeight))
            tick.addLine(to: CGPoint(x: x, y: y + marker.tickHeight))
            canvas.stroke(tick, with: .color(.white.opacity(marker.opacity)), lineWidth: marker.lineWidth)
            drawAxisLabel(marker.label, at: CGPoint(x: x, y: y + 19), in: &canvas)
            drawAxisLabel(String(format: "%.2fs", markerTime), at: CGPoint(x: x, y: y + 34), in: &canvas)
        }

        let phase = abs(rotationState.bodySpinAngle).truncatingRemainder(dividingBy: 2.0 * Double.pi)
        let playheadFraction = CGFloat(phase / (2.0 * Double.pi))
        let playheadX = start.x + (end.x - start.x) * playheadFraction
        var playhead = Path()
        playhead.move(to: CGPoint(x: playheadX, y: y - 18))
        playhead.addLine(to: CGPoint(x: playheadX, y: y + 10))
        canvas.stroke(playhead, with: .color(.white.opacity(0.72)), lineWidth: 1.4)
        canvas.fill(Path(ellipseIn: CGRect(x: playheadX - 4, y: y - 22, width: 8, height: 8)), with: .color(.white.opacity(0.72)))

        drawAxisLabel(String(localized: "particleDebug.orientation.timeline"), at: CGPoint(x: (start.x + end.x) * 0.5, y: y - 18), in: &canvas)
        drawAxisLabel(String(localized: "particleDebug.orientation.playhead"), at: CGPoint(x: playheadX, y: y - 34), in: &canvas)
    }

    private struct RotationMarker {
        let degrees: Double
        let label: String
        let tickHeight: CGFloat
        let lineWidth: CGFloat
        let opacity: Double
    }

    private func rotationMarkers(direction: ParticleSpinDirection) -> [RotationMarker] {
        if direction.rotatesVertically {
            let firstDirectionKey = direction == .up
                ? "particleDebug.direction.up"
                : "particleDebug.direction.down"
            let oppositeDirectionKey = direction == .up
                ? "particleDebug.direction.down"
                : "particleDebug.direction.up"
            return [
                RotationMarker(degrees: 0, label: "0°\n\(String(localized: "particleDebug.orientation.front"))", tickHeight: 11, lineWidth: 1.5, opacity: 0.64),
                RotationMarker(degrees: 45, label: "45°\n\(String(localized: String.LocalizationValue(firstDirectionKey)))", tickHeight: 7, lineWidth: 1.0, opacity: 0.36),
                RotationMarker(degrees: 90, label: "90°\n\(String(localized: String.LocalizationValue(firstDirectionKey)))", tickHeight: 9, lineWidth: 1.2, opacity: 0.50),
                RotationMarker(degrees: 135, label: "135°", tickHeight: 6, lineWidth: 1.0, opacity: 0.28),
                RotationMarker(degrees: 180, label: "180°\n\(String(localized: "particleDebug.orientation.back"))", tickHeight: 10, lineWidth: 1.3, opacity: 0.56),
                RotationMarker(degrees: 225, label: "225°", tickHeight: 6, lineWidth: 1.0, opacity: 0.28),
                RotationMarker(degrees: 270, label: "270°\n\(String(localized: String.LocalizationValue(oppositeDirectionKey)))", tickHeight: 9, lineWidth: 1.2, opacity: 0.50),
                RotationMarker(degrees: 315, label: "315°\n\(String(localized: String.LocalizationValue(oppositeDirectionKey)))", tickHeight: 7, lineWidth: 1.0, opacity: 0.36),
                RotationMarker(degrees: 360, label: "360°\n\(String(localized: "particleDebug.orientation.front"))", tickHeight: 11, lineWidth: 1.5, opacity: 0.64)
            ]
        }
        let isReversed = direction == .left
        return [
            RotationMarker(degrees: 0, label: "0°\n\(String(localized: "particleDebug.orientation.front"))", tickHeight: 11, lineWidth: 1.5, opacity: 0.64),
            RotationMarker(degrees: 45, label: "45°\n\(String(localized: isReversed ? "particleDebug.orientation.left45" : "particleDebug.orientation.right45"))", tickHeight: 7, lineWidth: 1.0, opacity: 0.36),
            RotationMarker(degrees: 90, label: "90°\n\(String(localized: isReversed ? "particleDebug.orientation.leftSide" : "particleDebug.orientation.rightSide"))", tickHeight: 9, lineWidth: 1.2, opacity: 0.50),
            RotationMarker(degrees: 135, label: "135°", tickHeight: 6, lineWidth: 1.0, opacity: 0.28),
            RotationMarker(degrees: 180, label: "180°\n\(String(localized: "particleDebug.orientation.back"))", tickHeight: 10, lineWidth: 1.3, opacity: 0.56),
            RotationMarker(degrees: 225, label: "225°", tickHeight: 6, lineWidth: 1.0, opacity: 0.28),
            RotationMarker(degrees: 270, label: "270°\n\(String(localized: isReversed ? "particleDebug.orientation.rightSide" : "particleDebug.orientation.leftSide"))", tickHeight: 9, lineWidth: 1.2, opacity: 0.50),
            RotationMarker(degrees: 315, label: "315°\n\(String(localized: isReversed ? "particleDebug.orientation.right45" : "particleDebug.orientation.left45"))", tickHeight: 7, lineWidth: 1.0, opacity: 0.36),
            RotationMarker(degrees: 360, label: "360°\n\(String(localized: "particleDebug.orientation.front"))", tickHeight: 11, lineWidth: 1.5, opacity: 0.64)
        ]
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

    private func drawAxisLabel(_ value: String, at point: CGPoint, in canvas: inout GraphicsContext) {
        canvas.draw(
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52)),
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
            defaultColorProfile: controller.particleColorProfile,
            setShellMode: controller.setParticleShellMode,
            setRenderKind: controller.setParticleRenderKind,
            rebuildFixedSeed: presentationSettings.rebuildWithFixedSeed,
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
    let defaultColorProfile: ParticleColorProfile
    let setShellMode: (ParticleShellMode) -> Void
    let setRenderKind: (ParticleRenderKind) -> Void
    let rebuildFixedSeed: () -> Void
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

            Toggle(String(localized: "particleDebug.orientation.overlay"), isOn: $orientationOverlayVisible)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)

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
                        ForEach(ParticleTuningParameter.allCases) { parameter in
                            ParticleParameterRow(parameter: parameter, tuning: $tuning)
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
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.previousVisualState", value: snapshot.previousVisualState)
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.stateElapsedTime", value: String(format: "%.2fs", snapshot.stateElapsedTime))
                ParticleDiagnosticsRow(labelKey: "particleDebug.diagnostics.lastTransitionReason", value: snapshot.lastTransitionReason)
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
