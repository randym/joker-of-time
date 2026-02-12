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
    static let credentialsCleared = Notification.Name("CredentialsCleared")
    static let sessionStateDidChange = Notification.Name("SessionStateDidChange")
    /// Post when Settings window close is blocked by invalid URL; view should focus URL field and show inline error.
    static let settingsFocusURLField = Notification.Name("SettingsFocusURLField")
    /// Post when Settings should open and focus the Node path field (e.g. after dismissing Node not found prompt).
    static let settingsFocusNodePathField = Notification.Name("SettingsFocusNodePathField")
    /// Post when Settings should open and focus the credentials username field (e.g. after dismissing Login failed prompt).
    static let settingsFocusCredentialsField = Notification.Name("SettingsFocusCredentialsField")
    
    // Prompt action events
    static let promptStartWorkClockIn = Notification.Name("PromptStartWorkClockIn")
    static let promptStartWorkDismiss = Notification.Name("PromptStartWorkDismiss")
    static let promptStopWorkClockOut = Notification.Name("PromptStopWorkClockOut")
    static let promptStopWorkKeepWorking = Notification.Name("PromptStopWorkKeepWorking")
    static let promptAlreadyClockedInDismiss = Notification.Name("PromptAlreadyClockedInDismiss")
    static let promptCannotClockOutDismiss = Notification.Name("PromptCannotClockOutDismiss")
    static let promptNotClockedInDismiss = Notification.Name("PromptNotClockedInDismiss")
    static let promptAlreadyClockedOutDismiss = Notification.Name("PromptAlreadyClockedOutDismiss")
    static let promptNetworkOfflineDismiss = Notification.Name("PromptNetworkOfflineDismiss")
    static let promptLoginFailedDismiss = Notification.Name("PromptLoginFailedDismiss")
    static let promptCredentialsRequiredGoToSettings = Notification.Name("PromptCredentialsRequiredGoToSettings")
    static let promptSomethingWentWrongDismiss = Notification.Name("PromptSomethingWentWrongDismiss")
    static let promptNodeNotFoundDismiss = Notification.Name("PromptNodeNotFoundDismiss")
    static let promptCannotReachSiteDismiss = Notification.Name("PromptCannotReachSiteDismiss")
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
        AppLogger.info("Launch: fetching timecard status from King of Time (startup, with backoff, will update session state)")
        AutomationController.shared.requestResync(source: .startup)

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
                AppLogger.info("Launch: wake — fetching timecard status from King of Time (with backoff retry, will update session state)")
                AutomationController.shared.requestResync(source: .wake)
            }
        }

        // When we come back online, sync timecard so icon and state update without user action.
        NotificationCenter.default.addObserver(
            forName: NetworkMonitor.connectivityDidChangeNotification,
            object: nil,
            queue: .main
        ) { note in
            guard note.userInfo?["isConnected"] as? Bool == true else { return }
            AppLogger.info("Launch: network back online, fetching timecard status from King of Time (with backoff retry, will update session state)")
            AutomationController.shared.requestResync(source: .network)
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

/// Log in (if needed), fetch and parse King of Time timecard, update session state, and show start-work prompt if appropriate. Call only when credentials exist.
func runTimeCardTask(context: PreflightUIContext = .startup) {
    AppLogger.info("runTimeCardTask: context=\(context) — fetching timecard status from King of Time (with backoff, will update session state)")
    BackoffRetryRunner.run(command: ResyncCommand(context: context)) { result in
        if case .failure(let error) = result, let preflightErr = error as? PreflightFailureError {
            PreflightUIHandler.handleFailure(preflightErr.failure, context: context)
        }
    }
}

/// Manual sync from the menu: run preflight once (no backoff). On success, refresh timecard;
/// on failure, route through PreflightUIHandler with `.manualSync`.
/// Helper for user-initiated automation (clock in/out, sync): run preflight once,
/// then either execute `action` (on success) or route failure via PreflightUIHandler.
func runUserAutomationWithPreflight(label: String, action: @escaping () -> Void) {
    AppLogger.info("runUserAutomationWithPreflight[\(label)]: starting preflight")
    DispatchQueue.global(qos: .userInitiated).async {
        let outcome = PreflightRunner.runPreflightOutcome()
        DispatchQueue.main.async {
            if outcome.success {
                AppLogger.info("runUserAutomationWithPreflight[\(label)]: preflight OK, running action")
                action()
            } else if let failure = outcome.failure {
                PreflightUIHandler.handleFailure(failure, context: .manualSync)
            }
        }
    }
}

/// Wraps `PreflightFailure` so it can be returned from `RetryableCommand.execute()` and passed to the retry completion.
struct PreflightFailureError: Error {
    let failure: PreflightFailure
    
    /// Whether this failure is transient and should be retried.
    var isTransient: Bool {
        failure.isTransient
    }
}

/// Command for resync contexts (startup, auto-resync, manual sync): run preflight with
/// backoff then (on success) run automation + session handling.
struct ResyncCommand: RetryableCommand {
    let context: PreflightUIContext

    func execute() -> Result<Void, Error> {
        let outcome = PreflightRunner.runPreflightOutcome()
        guard outcome.success else {
            if let f = outcome.failure {
                let error = PreflightFailureError(failure: f)
                return .failure(error)
            }
            return .failure(PreflightFailureError(failure: PreflightFailure(reasonKey: "preflight.unknown", iconName: "exclamationmark.triangle", kind: .unknown, isTransient: false)))
        }
        AppLogger.info("ResyncCommand: context=\(context) — fetching timecard status from King of Time and updating session state")
        AutomationInvoker.shared.runAppStartLog()
        SessionManager.shared.handleLaunch()
        return .success(())
    }
}

/// Command for user-initiated Clock In. Performs clock-in via AutomationInvoker and routes
/// success/failure through SessionManager helpers. Preflight is run by AutomationController
/// before this command executes.
struct ClockInCommand: RetryableCommand {
    func execute() -> Result<Void, Error> {
        let session = SessionManager.shared
        session.objectWillChange.send()
        session.isAutomationRunning = true
        let (ok, output) = AutomationInvoker.shared.runClockSync(action: .clockIn)
        session.isAutomationRunning = false
        if ok {
            session.onClockInAutomationSucceeded()
            return .success(())
        } else {
            session.onClockInAutomationFailed(output: output)
            let error = NSError(domain: "ClockInCommand", code: -1, userInfo: [
                NSLocalizedDescriptionKey: output
            ])
            return .failure(error)
        }
    }
}

/// Command for user-initiated Clock Out. Performs clock-out via AutomationInvoker and routes
/// success/failure through SessionManager helpers. Preflight is run by AutomationController
/// before this command executes.
struct ClockOutCommand: RetryableCommand {
    func execute() -> Result<Void, Error> {
        let session = SessionManager.shared
        session.objectWillChange.send()
        session.isAutomationRunning = true
        let (ok, output) = AutomationInvoker.shared.runClockSync(action: .clockOut)
        session.isAutomationRunning = false
        if ok {
            session.onClockOutAutomationSucceeded()
            return .success(())
        } else {
            session.onClockOutAutomationFailed(output: output)
            let error = NSError(domain: "ClockOutCommand", code: -1, userInfo: [
                NSLocalizedDescriptionKey: output
            ])
            return .failure(error)
        }
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
    BackoffRetryRunner.run(command: ResyncCommand(context: .autoResync)) { result in
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
