import AppKit
import SwiftUI

// Separate window for Settings so we can show a richer UI than the tiny popover.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    /// Current URL field content (trimmed). Updated by SettingsView.
    private(set) var currentURLString: String = ""

    /// Current credentials field content. Updated by SettingsView so we can save on close only when changed.
    private(set) var currentCredentialsUsername: String = ""
    private(set) var currentCredentialsPassword: String = ""

    private override init() {
        super.init()
    }

    func setCurrentURLString(_ trimmed: String) {
        currentURLString = trimmed
    }

    func setCurrentCredentials(username: String, password: String) {
        currentCredentialsUsername = username
        currentCredentialsPassword = password
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

        setCurrentURLString(AppSettings.shared.kotBaseURL)
        AppLogger.info("Settings: show() — synced currentURLString=\(AppSettings.shared.kotBaseURL.isEmpty ? "(empty)" : AppSettings.shared.kotBaseURL)")

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }

    /// When Settings closes, save credentials to keychain if login ID or password changed, stop daemon so next run uses new account, then re-run preflight when appropriate.
    func windowWillClose(_ notification: Notification) {
        let un = currentCredentialsUsername.trimmingCharacters(in: .whitespaces)
        let pw = currentCredentialsPassword
        let stored = CredentialsManager.shared.loadCredentials()
        let usernameChanged = stored?.username != un
        let passwordEntered = !pw.isEmpty
        let credentialsChanged = usernameChanged || passwordEntered

        if credentialsChanged {
            let effectivePassword = pw.isEmpty ? (stored?.password ?? "") : pw
            if !un.isEmpty || !effectivePassword.isEmpty {
                if CredentialsManager.shared.saveCredentials(username: un, password: effectivePassword) {
                    AppLogger.info("Settings: credentials updated on close, stopping daemon and re-running preflight")
                    SessionManager.shared.clearSessionStateForNewCredentials()
                }
            } else {
                CredentialsManager.shared.clearCredentials()
                AutomationInvoker.shared.stopDaemon()
                SessionManager.shared.onCredentialsCleared()
            }
        }

        // Only trigger a resync when we actually have stored credentials. If the user
        // closes Settings without entering credentials, leave the app in a clear
        // \"credentials needed\" state and let the next user-initiated command re-run
        // preflight and reopen Settings.
        if let nowStored = CredentialsManager.shared.loadCredentials(),
           !nowStored.username.trimmingCharacters(in: .whitespaces).isEmpty,
           !nowStored.password.isEmpty {
            AppLogger.info("Settings: window closed with stored credentials, fetching timecard status from King of Time (with backoff retry, will update session state)")
            AutomationController.shared.requestResync(source: .settingsClose)
        } else {
            AppLogger.info("Settings: window closed without stored credentials; skipping fetch of timecard status from King of Time")
        }
    }

}
