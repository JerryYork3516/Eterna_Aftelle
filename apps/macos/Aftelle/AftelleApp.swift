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
