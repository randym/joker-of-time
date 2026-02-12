import AppKit
import SwiftUI

// About window (SwiftUI AboutView), shown from the menu bar menu.
final class AboutWindowController {
    static let shared = AboutWindowController()
    private var panel: NSPanel?

    private init() {}

    func show(status: String, host: String, username: String?, nodeVersion: String) {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        self.panel = nil

        let rootView = AboutView(
            status: status,
            host: host,
            username: username,
            nodeVersion: nodeVersion
        )
        let hosting = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.string("menu.about")
        panel.contentViewController = hosting
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        self.panel = panel

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
