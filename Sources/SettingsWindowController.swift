import AppKit
import SwiftUI

// Separate window for Settings so we can show a richer UI than the tiny popover.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    /// When non-nil, the Settings window must not close (URL invalid or HTTP in production). Updated by SettingsView.
    private(set) var validationError: String?

    /// Current URL field content (trimmed). Updated by SettingsView so we can validate on window close even if view state is stale.
    private(set) var currentURLString: String = ""

    private override init() {
        super.init()
    }

    func setValidationError(_ message: String?) {
        validationError = message
    }

    func setCurrentURLString(_ trimmed: String) {
        currentURLString = trimmed
        validationError = AppSettings.kotURLValidationError(trimmed: trimmed)
    }

    func show() {
        if let w = window {
            NSApp.setActivationPolicy(.regular)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("window.settings")
        window.contentViewController = hosting
        window.delegate = self
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        let effective = AppSettings.shared.effectiveKotBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        setCurrentURLString(effective)
        AppLogger.info("Settings: show() — synced currentURLString=\(effective.isEmpty ? "(empty)" : effective), validationError=\(validationError != nil ? "set" : "nil")")

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let trimmed = currentURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = AppSettings.kotURLValidationError(trimmed: trimmed)
        AppLogger.verbose("Settings: windowShouldClose — currentURLString=\(trimmed.isEmpty ? "(empty)" : trimmed), validator err=\(err ?? "nil"), allowingClose=\(err == nil)")
        guard err == nil else {
            validationError = err
            AppLogger.verbose("Settings: windowShouldClose — blocking close, posting settingsFocusURLField and showing alert")
            NotificationCenter.default.post(name: .settingsFocusURLField, object: nil)
            showValidationAlert()
            // After user dismisses alert: next run loop so modal is fully gone, then open Settings and focus URL.
            DispatchQueue.main.async { [weak self] in
                self?.show()
                NotificationCenter.default.post(name: .settingsFocusURLField, object: nil)
            }
            return false
        }
        return true
    }

    /// When Settings closes with valid URL and credentials, sync timecard so icon and preflight return to normal.
    func windowWillClose(_ notification: Notification) {
        let trimmed = currentURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppSettings.kotURLValidationError(trimmed: trimmed) == nil,
              CredentialsManager.shared.hasStoredCredentials else { return }
        AppLogger.info("Settings: window closed with valid URL and credentials, running time card task with backoff retry")
        runBackgroundResync(source: "settingsClose") { result in
            if case .failure(let error) = result, let preflightErr = error as? PreflightFailureError {
                PreflightUIHandler.handleFailure(preflightErr.failure, context: .settingsClose)
            }
        }
    }

    /// Call when Close is blocked so the user sees why.
    func showValidationAlert() {
        let msg = validationError ?? L10n.string("settings.fix_url_to_close")
        let alert = NSAlert()
        alert.messageText = L10n.string("settings.cannot_close_invalid.title")
        alert.informativeText = msg
        alert.alertStyle = .warning
        if #available(macOS 11.0, *) {
            alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: L10n.string("alert.error_icon"))
        }
        alert.addButton(withTitle: L10n.string("settings.cannot_close_invalid.ok"))
        alert.runModal()
    }
}
