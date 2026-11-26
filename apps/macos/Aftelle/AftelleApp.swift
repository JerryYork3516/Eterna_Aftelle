import AppKit
import SwiftUI

@MainActor
private final class AftelleApplicationDelegate: NSObject,
    NSApplicationDelegate {
    weak var controller: AppController?
    private var terminationInFlight = false

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        guard !terminationInFlight else { return .terminateLater }
        terminationInFlight = true
        Task { @MainActor [weak self, weak controller] in
            guard let self, let controller else {
                sender.reply(toApplicationShouldTerminate: true)
                return
            }
            await controller.shutdownSpeechAudioHost()
            controller.persistForNormalTerminationIfPossible()
            sender.reply(toApplicationShouldTerminate: true)
            self.terminationInFlight = false
        }
        return .terminateLater
    }
}

@main
private enum AftelleEntry {
    @MainActor
    static func main() {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if AppleNativeVoiceAcousticLabLaunch.isRequested(arguments) {
                #if APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED && APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED
                    if AppleNativeVoiceAcousticLabLaunch.isAllowed(
                        arguments, deviceBuildAuthorized: AppleNativeVoiceDebugAdmission.deviceBuildAuthorized
                    ) {
                        NativeVoiceAcousticLabApp.main()
                    }
                #endif
                return
            }
        #endif
        AftelleApp.main()
    }
}
struct AftelleApp: App {
    @NSApplicationDelegateAdaptor(AftelleApplicationDelegate.self)
    private var appDelegate
    @StateObject private var controller = AppController()
    @StateObject private var presentationSettings = ParticlePresentationSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        Window("Aftelle", id: "main-window") {
            ContentView(controller: controller, presentationSettings: presentationSettings)
                .onAppear {
                    appDelegate.controller = controller
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(String(localized: "app.menu.quit")) {
                    NSApplication.shared.terminate(nil)
                }
            }
            #if DEBUG
            CommandMenu(String(localized: "particleDebug.menu.title")) {
                Button(String(localized: "particleDebug.menu.togglePanel")) {
                    controller.toggleParticleDebugPanel()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button(String(localized: "particleDebug.menu.shellMode")) {}
                    .disabled(true)
                Button(shellMenuTitle(.darkShell)) {
                    controller.setParticleShellMode(.darkShell)
                }
                Button(shellMenuTitle(.immersiveShell)) {
                    controller.setParticleShellMode(.immersiveShell)
                }
                Button(shellMenuTitle(.transparentShell)) {
                    controller.setParticleShellMode(.transparentShell)
                }

                Divider()

                Button(String(localized: "particleDebug.menu.renderAdapter")) {}
                    .disabled(true)
                ForEach(ParticleRenderKind.allCases) { kind in
                    Button(renderMenuTitle(kind)) {
                        controller.setParticleRenderKind(kind)
                    }
                }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                controller.markSessionUncleanIfPossible()
            } else if phase == .inactive || phase == .background {
                controller.markSessionUncleanIfPossible()
            }
        }

        #if DEBUG
        Window(String(localized: "particleDebug.windowTitle"), id: ParticleDebugWindow.sceneID) {
            ParticleDebugWindow(controller: controller, presentationSettings: presentationSettings)
        }
        .defaultSize(width: 560, height: 640)
        .windowResizability(.contentMinSize)
        #endif
    }

    #if DEBUG
    private func shellMenuTitle(_ mode: ParticleShellMode) -> String {
        let title = String(localized: String.LocalizationValue(mode.localizedKey))
        return controller.particleShellMode == mode ? "\(title) ✓" : title
    }

    private func renderMenuTitle(_ kind: ParticleRenderKind) -> String {
        let title = String(localized: String.LocalizationValue(kind.localizedKey))
        return controller.particleRenderKind == kind ? "\(title) ✓" : title
    }
    #endif
}

#if DEBUG && APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED && APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED
private struct NativeVoiceAcousticLabApp: App {
    @NSApplicationDelegateAdaptor(AftelleApplicationDelegate.self)
    private var appDelegate
    @StateObject private var controller = AppController()

    var body: some Scene {
        Window(String(localized: "nativeVoiceAcousticLab.title"), id: "native-voice-acoustic-lab") {
            NativeVoiceAcousticLabView(controller: controller)
                .task {
                    appDelegate.controller = controller
                    await controller.prepareNativeVoiceAcousticLab()
                }
        }
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentMinSize)
    }
}

private struct NativeVoiceAcousticLabView: View {
    private enum Stage: String, CaseIterable {
        case residentOnly, nearEndOnly, doubleTalk, multiTurn
    }

    @ObservedObject var controller: AppController
    @State private var stage: Stage = .residentOnly
    @State private var showsStartConsent = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let evidence = controller.nativeVoiceAcousticLabEvidencePhase
            let graph = controller.nativeVoiceAcousticLabLiveGraph
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    deviceStatus(graph)
                    Divider()
                    sessionControls(evidence)
                    Divider()
                    stageControls(graph: graph, evidence: evidence)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 460, minHeight: 390)
        .alert(text("start"), isPresented: $showsStartConsent) {
            Button(text("start")) {
                stage = .residentOnly
                Task { await controller.startNativeVoiceAcousticLab() }
            }
            Button(String(localized: "nativeVoiceAcousticEvidence.cancel"), role: .cancel) {}
        } message: {
            Text(text("startConsent"))
        }
    }

    private func deviceStatus(_ graph: NativeVoiceTransportReadback?) -> some View {
        let devices = controller.nativeVoiceAcousticLabDevices
        let vp = graph?.voiceProcessing
        return VStack(alignment: .leading, spacing: 6) {
            LabeledContent(text("preflight"), value: text("preflight.\(controller.nativeVoiceAcousticLabPreflight.rawValue)"))
            LabeledContent(text("input"), value: deviceName(devices?.inputDevice))
            LabeledContent(text("output"), value: deviceName(devices?.outputDevice))
            if let devices {
                LabeledContent(text("microphone"), value: text("microphone.\(devices.authorization.rawValue)"))
            }
            if let route = graph?.route {
                LabeledContent(text("audioUnitRoute"), value: "\(route.inputUnitDevice) / \(route.outputUnitDevice)")
            }
            LabeledContent(text("voiceProcessing"), value: setting(vp.map { $0.inputEnabled && $0.outputEnabled && !$0.bypassed }))
            LabeledContent(text("agc"), value: setting(vp?.agcEnabled))
            ForEach(["sink", "source", "output"], id: \.self) { node in
                LabeledContent(text("format.\(node)"), value: format(graph?.formats[node]))
            }
            HStack {
                Button(text("refresh")) {
                    Task { await controller.refreshNativeVoiceAcousticLabReadback() }
                }
                .disabled(devices == nil || controller.realtimeFullDuplexSpeechStatus.phase == .starting)
                if controller.nativeVoiceAcousticLabPreflight == .microphoneRequired {
                    Button(text("requestMicrophone")) {
                        Task { await controller.requestNativeVoiceAcousticLabMicrophone() }
                    }
                }
            }
        }
    }

    private func sessionControls(_ evidence: MacSpeechNativeAcousticEvidence.Phase) -> some View {
        let failure = controller.nativeVoiceAcousticLabFailure
        let providerStatus = if controller.nativeVoiceAcousticLabProviderSessionOpen {
            text("provider.open")
        } else if failure?.stage == .providerConnection {
            text("provider.failed")
        } else if controller.realtimeFullDuplexSpeechStatus.phase == .starting {
            text("provider.opening")
        } else {
            text("provider.idle")
        }
        let evidenceAction = switch evidence {
        case .off: String(localized: "nativeVoiceAcousticEvidence.arm")
        case .ended: text("saveOrRevoke")
        case .saved, .saving, .cleanupFailed: String(localized: "nativeVoiceAcousticEvidence.revoke")
        default: String(localized: "nativeVoiceAcousticEvidence.title")
        }
        return VStack(alignment: .leading, spacing: 6) {
            LabeledContent(text("provider"), value: providerStatus)
            LabeledContent(text("session"), value: String(describing: controller.realtimeFullDuplexSpeechStatus.phase))
            LabeledContent(String(localized: "nativeVoiceAcousticEvidence.title"), value: text("evidence.\(evidence)"))
            if let status = controller.realtimeSpeechDiagnosticStatusKey {
                Text(String(localized: String.LocalizationValue(status)))
                    .foregroundStyle(.secondary)
            }
            if let failure {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent(text("failureStage"), value: text("failure.\(failure.stage.rawValue)"))
                    LabeledContent(text("routeError"), value: failure.code)
                    LabeledContent(text("errorDomain"), value: failure.domain ?? "UNKNOWN")
                    LabeledContent(text("errorCode"), value: failure.underlyingCode.map(String.init) ?? "UNKNOWN")
                }
                .textSelection(.enabled)
            }
            HStack {
                Button(evidenceAction, action: controller.manageNativeVoiceAcousticLabEvidence)
                    .disabled(evidence == .revoked || evidence == .revoking
                        || (evidence == .off && controller.nativeVoiceAcousticLabPreflight != .ready))
                Button(text("start")) { showsStartConsent = true }
                    .disabled(!controller.canStartNativeVoiceAcousticLab)
                Button(text("stop")) {
                    Task { await controller.stopRealtimeFullDuplexSpeech() }
                }
                .disabled(!controller.canStopRealtimeFullDuplexSpeech)
            }
        }
    }

    private func stageControls(
        graph: NativeVoiceTransportReadback?, evidence: MacSpeechNativeAcousticEvidence.Phase
    ) -> some View {
        let ready = evidence == .recording && graph?.lastConsumedSink != nil
            && graph?.voiceProcessing?.inputEnabled == true && graph?.voiceProcessing?.outputEnabled == true
            && graph?.voiceProcessing?.agcEnabled == true && graph?.voiceProcessing?.bypassed == false
            && graph?.voiceProcessing?.inputMuted == false
        return VStack(alignment: .leading, spacing: 8) {
            Picker(text("stage"), selection: $stage) {
                ForEach(Stage.allCases, id: \.self) { value in
                    Text(text("stage.\(value.rawValue)")).tag(value)
                }
            }
            .disabled(!ready)
            Text(text(ready ? "windows.\(stage.rawValue)" : "windows.hold"))
        }
    }

    private func text(_ key: String) -> String {
        String(localized: String.LocalizationValue("nativeVoiceAcousticLab.\(key)"))
    }

    private func setting(_ state: Bool?) -> String {
        switch state {
        case true: "ON"
        case false: "OFF"
        case nil: "UNKNOWN"
        }
    }

    private func deviceName(_ device: MacSpeechAudioDevice?) -> String {
        guard let device else { return "UNKNOWN" }
        return device.isAvailable ? device.name : text("preflight.deviceUnavailable")
    }

    private func format(_ format: NativeVoiceIOFormat?) -> String {
        guard let format else { return "UNKNOWN" }
        let layout = text(format.interleaved ? "format.interleaved" : "format.planar")
        return "\(format.sampleRate.formatted()) Hz · \(format.channels) ch · Float32 · \(layout)"
    }
}
#endif
