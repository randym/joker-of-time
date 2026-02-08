import SwiftUI
import AppKit

@main
struct JokerOfTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let closeCredentialsWindow = Notification.Name("CloseCredentialsWindow")
    static let credentialsCleared = Notification.Name("CredentialsCleared")
    static let sessionStateDidChange = Notification.Name("SessionStateDidChange")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func applySystemAppearance() {
        let isDark: Bool
        if let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain),
           let style = global["AppleInterfaceStyle"] as? String {
            isDark = (style == "Dark")
        } else {
            isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: if another JokerOfTime is already running, activate it and quit this launch.
        let bundleId = Bundle.main.bundleIdentifier ?? "io.github.randym.JokerOfTime"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if let other = running.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
            return
        }

        applySystemAppearance()
        logLocale()
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(applySystemAppearance),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        AppLogger.info("App launched")
        StatusItemManager.shared.setup()
        LoginItemManager.shared.setEnabled(AppSettings.shared.runOnLogin)

        if !CredentialsManager.shared.hasStoredCredentials {
            AppLogger.info("Startup: no credentials, showing credentials window")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                CredentialsWindowController.shared.show()
            }
            // Do not run node check or handleLaunch until we have credentials.
        } else {
            runTimeCardTask()
        }

        NotificationCenter.default.addObserver(
            forName: .closeCredentialsWindow,
            object: nil,
            queue: .main
        ) { _ in
            CredentialsWindowController.shared.close()
            if CredentialsManager.shared.hasStoredCredentials {
                AppLogger.info("Credentials saved: running time card task")
                SessionManager.shared.clearSessionStateForNewCredentials()
                DispatchQueue.main.async {
                    runTimeCardTask()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .credentialsCleared,
            object: nil,
            queue: .main
        ) { _ in
            SessionManager.shared.onCredentialsCleared()
        }

        // Fetch time card when system wakes from sleep (e.g. login-item app after user logs in or machine wakes).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            if CredentialsManager.shared.hasStoredCredentials {
                SessionManager.shared.recheckTimecardStatus()
            }
        }
    }

    private func logLocale() {
        guard AppEnvironment.isLocal else { return }
        let bundle = Bundle.main
        let path = bundle.bundlePath
        let id = bundle.bundleIdentifier ?? "—"
        let preferred = bundle.preferredLocalizations
        let preferredStr = preferred.isEmpty ? "[]" : preferred.joined(separator: ", ")
        let overrides = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] ?? []
        let overridesStr = overrides.isEmpty ? "none" : overrides.joined(separator: ", ")
        let msg = "[locale] bundlePath=\(path) | bundleId=\(id) | preferred=\(preferredStr) | AppleLanguages=\(overridesStr)"
        fputs(msg + "\n", stderr)
        AppLogger.info("Locale: bundlePath=\(path)")
        AppLogger.info("Locale: bundleId=\(id), preferredLocalizations=\(preferredStr), AppleLanguages override=\(overridesStr)")
        if preferred.first != overrides.first, !overrides.isEmpty {
            AppLogger.info("Locale: override set but preferred is \(preferredStr); ensure .lproj is in bundle or restart after defaults write.")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.info("Quit")
    }
}

/// Log in (if needed), fetch and parse time card, update state, and show start-work prompt if appropriate. Call only when credentials exist.
func runTimeCardTask() {
    _ = AutomationInvoker.shared.performStartupNodeCheck()
    AutomationInvoker.shared.runAppStartLog()
    SessionManager.shared.handleLaunch()
}

/// Environment (local vs production). Set at build time via build-app.sh; missing file (e.g. swift run) defaults to "local".
enum AppEnvironment {
    static var current: String {
        guard let url = Bundle.main.url(forResource: "environment", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return "local" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static var isLocal: Bool { current == "local" }
}
