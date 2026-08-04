import SwiftUI

@main
struct AftelleApp: App {
    @StateObject private var controller = AppController()
    @StateObject private var presentationSettings = ParticlePresentationSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Aftelle") {
            ContentView(controller: controller, presentationSettings: presentationSettings)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(String(localized: "app.menu.quit")) {
                    #if DEBUG
                    Task { @MainActor in
                        await controller.shutdownSpeechAudioHost()
                        controller.persistForNormalTerminationIfPossible()
                        NSApplication.shared.terminate(nil)
                    }
                    #else
                    controller.persistForNormalTerminationIfPossible()
                    NSApplication.shared.terminate(nil)
                    #endif
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
