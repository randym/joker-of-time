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
    /// Post when Settings window close is blocked by invalid URL; view should focus URL field and show inline error.
    static let settingsFocusURLField = Notification.Name("SettingsFocusURLField")
    /// Post when Settings should open and focus the Node path field (e.g. after dismissing Node not found prompt).
    static let settingsFocusNodePathField = Notification.Name("SettingsFocusNodePathField")
    /// Post when Settings should open and focus the credentials username field (e.g. after dismissing Login failed prompt).
    static let settingsFocusCredentialsField = Notification.Name("SettingsFocusCredentialsField")
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

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppLogger.debug("Launch: applicationWillFinishLaunching entered")
        let args = ProcessInfo.processInfo.arguments.joined(separator: " ")
        let envKeys = Array(ProcessInfo.processInfo.environment.keys).sorted().joined(separator: ",")
        AppLogger.debug("Launch: args=\(args)")
        AppLogger.debug("Launch: envKeys=\(envKeys)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.debug("Launch: applicationDidFinishLaunching entered")
        AppLogger.debug("Launch: window snapshot at didFinish: count=\(NSApp.windows.count)")
        for window in NSApp.windows {
            AppLogger.debug("Launch: window title=\"\(window.title)\" isVisible=\(window.isVisible)")
        }

        // Single instance: if another JokerOfTime is already running, activate it and quit this launch.
        let bundleId = Bundle.main.bundleIdentifier ?? "io.github.randym.JokerOfTime"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if let other = running.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            AppLogger.info("Launch: another instance running, activating it and quitting")
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
        AppLogger.info("Launch: app launched")
        StatusItemManager.shared.setup()
        if !AppEnvironment.isLocal {
            LoginItemManager.shared.setEnabled(AppSettings.shared.runOnLogin)
        }
        NetworkMonitor.shared.start()
        _ = PreflightState.shared

        if !CredentialsManager.shared.hasStoredCredentials {
            AppLogger.info("Launch: no credentials → showing credentials window, not running timecard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                CredentialsWindowController.shared.show()
            }
            // Do not run node check or handleLaunch until we have credentials.
        } else {
            let effectiveURL = AppSettings.shared.effectiveKotBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if let invalidMsg = AppSettings.kotURLValidationError(trimmed: effectiveURL) {
                AppLogger.info("Launch: invalid URL (\(invalidMsg)) → opening Settings, not running timecard")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    SettingsWindowController.shared.show()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    NotificationCenter.default.post(name: .settingsFocusURLField, object: nil)
                }
            } else {
                AppLogger.info("Launch: has credentials + valid URL → running time card task with backoff")
                runTimeCardTask(context: .startup)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .closeCredentialsWindow,
            object: nil,
            queue: .main
        ) { _ in
            CredentialsWindowController.shared.close()
            if CredentialsManager.shared.hasStoredCredentials {
                AppLogger.info("Launch: credentials saved, running time card task")
                SessionManager.shared.clearSessionStateForNewCredentials()
                DispatchQueue.main.async {
                    runTimeCardTask(context: .startup)
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

        // Background triggers only: use backoff retry (transient failures common). User-initiated (launch, credentials saved, settings close) run once and fail.
        // Fetch time card when system wakes from sleep (e.g. login-item app after user logs in or machine wakes).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            if CredentialsManager.shared.hasStoredCredentials {
                AppLogger.info("Launch: wake — running time card task with backoff retry")
                runBackgroundResync(source: "wake") { result in
                    if case .failure(let error) = result, let preflightErr = error as? PreflightFailureError {
                        PreflightUIHandler.handleFailure(preflightErr.failure, context: .autoResync)
                    }
                }
            }
        }

        // When we come back online, sync timecard so icon and state update without user action.
        NotificationCenter.default.addObserver(
            forName: NetworkMonitor.connectivityDidChangeNotification,
            object: nil,
            queue: .main
        ) { note in
            guard note.userInfo?["isConnected"] as? Bool == true,
                  CredentialsManager.shared.hasStoredCredentials else { return }
            AppLogger.info("Launch: network back online, running time card task with backoff retry")
            runBackgroundResync(source: "network") { result in
                if case .failure(let error) = result, let preflightErr = error as? PreflightFailureError {
                    PreflightUIHandler.handleFailure(preflightErr.failure, context: .autoResync)
                }
            }
        }
    }

    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        AppLogger.info("Launch: application(_:shouldSaveApplicationState:)")
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppLogger.info("Launch: applicationShouldHandleReopen hasVisibleWindows=\(flag)")
        return true
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        AppLogger.info("Launch: applicationWillBecomeActive")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppLogger.info("Launch: applicationDidBecomeActive")
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
        AppLogger.debug("Locale: bundlePath=\(path), bundleId=\(id), preferred=\(preferredStr), AppleLanguages=\(overridesStr)")
        if preferred.first != overrides.first, !overrides.isEmpty {
            AppLogger.debug("Locale: override set but preferred is \(preferredStr); ensure .lproj is in bundle or restart after defaults write.")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.info("Launch: quit")
    }
}

/// Log in (if needed), fetch and parse time card, update state, and show start-work prompt if appropriate. Call only when credentials exist.
func runTimeCardTask(context: PreflightUIContext = .startup) {
    AppLogger.info("runTimeCardTask: context=\(context) (with backoff)")
    BackoffRetryRunner.run(command: StartupCommand(context: context)) { result in
        if case .failure(let error) = result, let preflightErr = error as? PreflightFailureError {
            PreflightUIHandler.handleFailure(preflightErr.failure, context: context)
        }
    }
}

/// Wraps `PreflightFailure` so it can be returned from `RetryableCommand.execute()` and passed to the retry completion.
struct PreflightFailureError: Error {
    let failure: PreflightFailure
}

/// Command for startup/manual contexts: run preflight with backoff then (on success) run automation + session handling.
struct StartupCommand: RetryableCommand {
    let context: PreflightUIContext

    func execute() -> Result<Void, Error> {
        let outcome = PreflightRunner.runPreflightOutcome()
        guard outcome.success else {
            if let f = outcome.failure {
                return .failure(PreflightFailureError(failure: f))
            }
            return .failure(PreflightFailureError(failure: PreflightFailure(reasonKey: "preflight.unknown", iconName: "exclamationmark.triangle", kind: .unknown)))
        }
        AppLogger.info("runTimeCardTask: context=\(context)")
        AutomationInvoker.shared.runAppStartLog()
        SessionManager.shared.handleLaunch()
        return .success(())
    }
}

/// Command for autoResync: run preflight then (on success) run automation + session handling. Conforms to `RetryableCommand` for backoff retry.
struct AutoResyncCommand: RetryableCommand {
    func execute() -> Result<Void, Error> {
        let outcome = PreflightRunner.runPreflightOutcome()
        guard outcome.success else {
            if let f = outcome.failure {
                return .failure(PreflightFailureError(failure: f))
            }
            return .failure(PreflightFailureError(failure: PreflightFailure(reasonKey: "preflight.unknown", iconName: "exclamationmark.triangle", kind: .unknown)))
        }
        AppLogger.info("runTimeCardTask: context=autoResync")
        AutomationInvoker.shared.runAppStartLog()
        SessionManager.shared.handleLaunch()
        return .success(())
    }
}

private var isBackgroundResyncInProgress = false

/// Run timecard sync with backoff retry. If a background resync is already in progress, skip and do not call completion.
func runBackgroundResync(source: String, completion: @escaping (Result<Void, Error>) -> Void) {
    if isBackgroundResyncInProgress {
        AppLogger.info("Background resync already in progress, skipping (\(source))")
        return
    }
    isBackgroundResyncInProgress = true
    BackoffRetryRunner.run(command: AutoResyncCommand()) { result in
        isBackgroundResyncInProgress = false
        completion(result)
    }
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
