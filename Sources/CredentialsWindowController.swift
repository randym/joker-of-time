import AppKit
import SwiftUI

final class CredentialsWindowController: NSObject, NSWindowDelegate {
    static let shared = CredentialsWindowController()
    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        self.window = nil

        let hosting = NSHostingController(rootView: CredentialsForm())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("window.credentials")
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // LSUIElement apps: defer bringing window to front so it appears after activation is committed.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
}
