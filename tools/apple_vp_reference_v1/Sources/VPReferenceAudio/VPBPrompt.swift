import AppKit
import Darwin
import VPReferenceCore

enum VPBClockRead {
    static func read(_ id: String) -> VPBClock {
        var base = mach_timebase_info_data_t()
        let result = mach_timebase_info(&base)
        let before = mach_absolute_time()
        let continuous = mach_continuous_time()
        let after = mach_absolute_time()
        return VPBClock(
            id: id, absoluteBefore: before, continuous: continuous, absoluteAfter: after,
            numerator: result == KERN_SUCCESS ? base.numer : 0, denominator: result == KERN_SUCCESS ? base.denom : 0)
    }
}

@MainActor
final class VPBPrompt {
    private let window: NSWindow
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = text("title")
        window.isReleasedWhenClosed = false
        label.frame = NSRect(x: 32, y: 32, width: 696, height: 256)
        label.font = NSFont.systemFont(ofSize: 32)
        label.alignment = .center
        window.contentView?.addSubview(label)
        window.center()
    }

    func confirm(mode: VPMode) throws -> VPBDisplayReceipt {
        label.stringValue = text("ready") + "\n" + mode.rawValue
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = text("title") + " " + mode.rawValue
        alert.informativeText = text("consent")
        alert.addButton(withTitle: text("confirm"))
        alert.addButton(withTitle: text("cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            throw EngineeringFailure(stage: .command, code: .promptUnconfirmed)
        }
        window.makeKeyAndOrderFront(nil)
        wait(0.05)
        let receipt = display(id: "PREFLIGHT", value: text("warming"), userConfirmed: true)
        try receipt.validate(id: "PREFLIGHT", requiresUser: true)
        return receipt
    }

    func cue(_ cue: VPBCue) throws -> VPBDisplayReceipt {
        let value =
            cue.phrase.map { text(cue == .soft ? "soft" : "speak") + "\n" + $0 }
            ?? text(cue == .postRoll ? "postRoll" : "quiet")
        return display(id: cue.rawValue, value: value)
    }

    func requireVisible() throws {
        guard window.isVisible, window.occlusionState.contains(.visible), NSApplication.shared.isActive else {
            throw EngineeringFailure(stage: .command, code: .promptUnconfirmed)
        }
    }

    func wait(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        for _ in 0..<64 {
            guard
                let event = NSApplication.shared.nextEvent(
                    matching: .any, until: deadline, inMode: .default, dequeue: true)
            else { break }
            NSApplication.shared.sendEvent(event)
            NSApplication.shared.updateWindows()
            if Date() >= deadline { break }
        }
    }

    func close() { window.close() }

    private func display(id: String, value: String, userConfirmed: Bool = false) -> VPBDisplayReceipt {
        let requested = VPBClockRead.read(id)
        label.stringValue = value
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let visible = window.isVisible && window.occlusionState.contains(.visible) && NSApplication.shared.isActive
        return VPBDisplayReceipt(
            cueID: id, requested: requested, displayed: VPBClockRead.read(id), visible: visible,
            userConfirmed: userConfirmed)
    }

    nonisolated static func localized(_ key: String) -> String {
        NSLocalizedString(key, tableName: "VPBPrompt", bundle: .module, comment: "VP-B research prompt")
    }

    private func text(_ key: String) -> String { Self.localized(key) }
}
