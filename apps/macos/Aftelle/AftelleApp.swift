import AppKit
import SwiftUI

#if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS && APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED && APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED
@preconcurrency import AVFoundation
import UniformTypeIdentifiers
#endif

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
            #if NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS
                if NativeVoiceSameFrameLaunch.isRequested(arguments) {
                    #if APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED && APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED
                        if NativeVoiceSameFrameLaunch.isAllowed(
                            arguments, authorized: AppleNativeVoiceDebugAdmission.deviceBuildAuthorized
                        ) {
                            NativeVoiceSameFrameLabApp.main()
                        }
                    #endif
                    return
                }
            #endif
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

#if DEBUG && NATIVE_VOICE_SAME_FRAME_DIAGNOSTICS && APPLE_NATIVE_VOICE_P4_DEVICE_AUTHORIZED && APPLE_NATIVE_VOICE_ACOUSTIC_EVIDENCE_AUTHORIZED
private struct NativeVoiceSameFrameLabApp: App {
    var body: some Scene {
        Window(String(localized: "nativeVoiceSameFrame.title"), id: "native-voice-same-frame") {
            NativeVoiceSameFrameLabView()
        }
        .defaultSize(width: 460, height: 260)
        .windowResizability(.contentMinSize)
    }
}

private struct NativeVoiceSameFrameLabView: View {
    @State private var resident: Data?
    @State private var fileName: String?
    @State private var consent = false
    @State private var retainWAV = false
    @State private var localStorageReady: Bool?
    @State private var task: Task<Void, Never>?
    @State private var report: DiagnosticExport?
    @State private var wav: Data?
    @State private var savedFolder: URL?
    @State private var saveStatus: SaveStatus = .idle
    @State private var status = "choose"

    private enum SaveStatus { case idle, saving, saved, failed }

    private nonisolated struct DiagnosticExport: Encodable, Sendable {
        let schemaVersion = 2
        let runID: UUID
        let residentWAVSHA256: String
        let buildBinarySHA256: String?
        let outcome: String
        let transport: NativeVoiceTransportReadback
        let captureWAV: NativeVoiceSameFrameCapture.Summary?
        let captureWAVSHA256: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: String.LocalizationValue("nativeVoiceSameFrame." + status)))
                .font(.headline)
            if let fileName {
                Text(fileName).textSelection(.enabled)
            }
            Toggle(String(localized: "nativeVoiceSameFrame.retainWAV"), isOn: $retainWAV)
                .disabled(task != nil || saveStatus == .saving || localStorageReady != true)
            Text(storageStatus)
                .foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "nativeVoiceSameFrame.choose")) { chooseResident() }
                    .disabled(task != nil || saveStatus == .saving)
                Button(String(localized: "nativeVoiceAcousticLab.start")) { consent = true }
                    .disabled(task != nil || resident == nil || saveStatus == .saving || localStorageReady != true)
                Button(String(localized: "nativeVoiceAcousticLab.stop")) { task?.cancel() }
                    .disabled(task == nil)
            }
            if let report {
                exportControls(report)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 190)
        .task {
            localStorageReady = await Task.detached(priority: .utility) {
                (try? AppController.preflightSameFrameLocalExport()) != nil
            }.value
        }
        .onDisappear {
            task?.cancel()
            if savedFolder == nil {
                report = nil
            }
            wav = nil
        }
        .alert(String(localized: "nativeVoiceSameFrame.title"), isPresented: $consent) {
            Button(String(localized: "nativeVoiceAcousticLab.start")) {
                guard task == nil, localStorageReady == true, let resident else { return }
                report = nil
                wav = nil
                savedFolder = nil
                saveStatus = .idle
                status = "starting"
                let enabled = retainWAV
                task = Task { await run(resident, retainWAV: enabled) }
            }
            Button(String(localized: "nativeVoiceAcousticEvidence.cancel"), role: .cancel) {}
        } message: {
            Text(retainWAV
                ? String(localized: "nativeVoiceSameFrame.wavConsent")
                : String(localized: "nativeVoiceSameFrame.consent"))
        }
    }

    private var storageStatus: String {
        switch localStorageReady {
        case .some(true): String(localized: "nativeVoiceSameFrame.storageReady")
        case .some(false): String(localized: "nativeVoiceSameFrame.storageUnavailable")
        case .none: String(localized: "nativeVoiceSameFrame.storageChecking")
        }
    }

    @ViewBuilder
    private func exportControls(_ report: DiagnosticExport) -> some View {
        if let savedFolder {
            Button(String(localized: "nativeVoiceSameFrame.reveal")) {
                let name = report.captureWAVSHA256 == nil
                    ? NativeVoiceSameFrameFiles.jsonName : NativeVoiceSameFrameFiles.wavName
                NSWorkspace.shared.activateFileViewerSelecting([savedFolder.appendingPathComponent(name)])
            }
        } else {
            if let capture = report.captureWAV {
                Text(capture.state == .complete
                    ? String(localized: "nativeVoiceSameFrame.wavReady")
                    : String(localized: "nativeVoiceSameFrame.wavIncomplete"))
            }
            Button(wav == nil
                ? String(localized: "nativeVoiceSameFrame.export")
                : String(localized: "nativeVoiceSameFrame.exportWAV")) { export(report) }
                .disabled(saveStatus == .saving)
            if saveStatus == .failed {
                Text(String(localized: "nativeVoiceSameFrame.saveFailed"))
            }
        }
    }

    private func chooseResident() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            resident = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
            fileName = resident == nil ? nil : url.lastPathComponent
            status = resident == nil ? "failed" : "ready"
        }
    }

    private func run(_ bookmark: Data, retainWAV: Bool) async {
        defer { task = nil }
        guard let source = try? AppController.readSameFrameResidentWAV(bookmark),
              source.pcm.count <= 12 * 48000,
              await AVCaptureDevice.requestAccess(for: .audio), !Task.isCancelled
        else {
            status = "failed"
            return
        }

        let graph = AppleNativeVoiceTransport.macOS(limits: .init(sameFrameDiagnostics: true))
        let identity = NativeVoiceIdentity(
            authority: .init(runtimeGeneration: 0, routeEpoch: 0, configurationID: 1),
            captureGeneration: 1, captureToken: 1, playbackEpoch: 1, playbackToken: 1
        )
        let runID = UUID()
        var capture = retainWAV ? NativeVoiceSameFrameCapture(identity: identity.capture) : nil
        let outcome: String
        do {
            try await graph.start(identity: identity)
            outcome = try await playAndObserve(source.pcm, using: graph, playback: identity.playback, capture: &capture)
                ? "finished" : "incomplete"
        } catch is CancellationError {
            outcome = "stopped"
        } catch {
            outcome = "failed"
        }
        await graph.close()
        if let result = await graph.readback(), result.sameFrameDiagnostics != nil {
            let recording = capture?.finish(endedNormally: outcome == "finished" && result.state == "closed"
                && !Task.isCancelled)
            let recordingWAV = recording?.pcm.map { AppController.encodeSameFrameWAV($0) }
            wav = recordingWAV?.bytes
            report = DiagnosticExport(
                runID: runID, residentWAVSHA256: source.sha256,
                buildBinarySHA256: AppController.sameFrameBuildSHA256(), outcome: outcome, transport: result,
                captureWAV: recording?.summary, captureWAVSHA256: recordingWAV?.sha256
            )
            status = outcome == "finished" && result.sameFrameDiagnostics?.complete == true
                ? "finished" : "incomplete"
        } else {
            status = "failed"
        }
    }

    private func playAndObserve(
        _ pcm: Data, using graph: AppleNativeVoiceTransport, playback: NativeVoiceIdentity.Playback,
        capture: inout NativeVoiceSameFrameCapture?
    ) async throws -> Bool {
        let clock = ContinuousClock()
        var deadline = clock.now + .seconds(5)
        var playAt: ContinuousClock.Instant?
        var sentEOS = false
        var began = false
        var offset = 0
        var sawNonzero = false
        var sawEOS = false
        while clock.now < deadline {
            try Task.checkCancellation()
            let batch = try await graph.bridgeService(maxCaptureFrames: 8192)
            try Task.checkCancellation()
            if playAt == nil, !batch.packets.isEmpty {
                let cue = clock.now
                playAt = cue + .seconds(3)
                deadline = cue + .seconds(15)
                status = "speak"
            }
            capture?.append(batch.packets)
            if status == "speak", clock.now >= deadline - .seconds(4) {
                status = "quiet"
            }
            if !began, let playAt, clock.now >= playAt {
                try await graph.beginPlayback(playback)
                began = true
            }
            if began, !sentEOS {
                if offset < pcm.count {
                    let end = min(pcm.count, offset + 4800)
                    if try await graph.enqueuePlayback(pcm.subdata(in: offset ..< end), identity: playback) {
                        offset = end
                    }
                } else {
                    sentEOS = try await graph.finishPlayback(identity: playback)
                }
            }
            sawNonzero = sawNonzero || batch.render.contains { $0.nonzeroFrames > 0 }
            sawEOS = sawEOS || batch.progress.renderHandoff
            try await Task.sleep(for: .milliseconds(5))
        }
        status = "ending"
        if playAt != nil, capture?.needsPackets == true {
            try Task.checkCancellation()
            // Read anything already queued at the deadline without waiting for more audio.
            let final = try await graph.bridgeService(maxCaptureFrames: 8192)
            capture?.append(final.packets)
            sawNonzero = sawNonzero || final.render.contains { $0.nonzeroFrames > 0 }
            sawEOS = sawEOS || final.progress.renderHandoff
        }
        return sawNonzero && sawEOS
    }

    private func export(_ report: DiagnosticExport) {
        guard saveStatus != .saving else { return }
        let audio = wav
        guard (audio == nil) == (report.captureWAVSHA256 == nil) else {
            saveStatus = .failed
            return
        }
        saveStatus = .saving
        Task {
            do {
                let directory = try await Task.detached(priority: .utility) {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    return try AppController.saveSameFrameLocalExport(
                        json: encoder.encode(report), wav: audio, runID: report.runID
                    )
                }.value
                savedFolder = directory
                wav = nil
                saveStatus = .saved
            } catch {
                saveStatus = .failed
            }
        }
    }
}
#endif
