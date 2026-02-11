import Foundation
import AppKit

final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var clockInTime: Date?
    @Published var targetClockOutTime: Date?
    @Published var clockedOutTime: Date?
    @Published var isWorking: Bool = false
    @Published var isOverTime: Bool = false
    /// True when clocked out today (can't clock in again until next day).
    @Published var isDoneForTheDay: Bool = false
    @Published var isAutomationRunning: Bool = false
    /// From last successful time card fetch; used for About dialog.
    @Published var lastKnownIsWorkingDay: Bool?
    /// Human-readable label for today's timecard row (e.g. "未打刻", "08:54 – 17:53（予定）", "08:54 – 18:12").
    @Published var todayLabel: String?

    /// Dev and production must not share: each uses its own key so settings/user data never leak between builds.
    private static var dontAskAgainKey: String { AppEnvironment.isLocal ? "KOTDontAskAgainDay.Dev" : "KOTDontAskAgainDay" }
    private static var lastKnownWorkingDayKey: String { AppEnvironment.isLocal ? "JOTLastKnownWorkingDay.Dev" : "JOTLastKnownWorkingDay" }
    /// Set by handleLaunch(); when the next preflight (time card fetch) completes, consider showing start-work prompt. Call on main.
    private var pendingStartPromptAfterPreflight = false

    /// Fetch time card and update state from KOT (source of truth). Runs in background; updates UI on main.
    private func refreshFromTimeCard() {
        objectWillChange.send()
        isAutomationRunning = true
        NotificationCenter.default.post(name: .sessionStateDidChange, object: nil)

        AutomationInvoker.shared.runTimecardStatus { [weak self] result in
            guard let self else { return }
            let done = {
                self.objectWillChange.send()
                self.isAutomationRunning = false
                self.considerStartPromptAfterPreflight()
            }
            switch result {
            case .success(let payload):
                PreflightState.shared.setSiteReachable(true)
                let workingDay = payload.shouldWorkToday
                AppLogger.info("Session: timecard success clockedIn=\(payload.clockedIn), clockedOut=\(payload.clockedOut), clockInTime=\(payload.clockInTime ?? "nil")")
                if payload.clockedOut {
                    // Done for the day: clocked in and out; cannot clock in again.
                    let clockIn: Date? = payload.clockInTime.flatMap { Self.today(atTime: $0) }
                    let clockOut: Date? = payload.clockOutTime.flatMap { Self.today(atTime: $0) }
                    DispatchQueue.main.async {
                        self.setLastKnownWorkingDay(workingDay)
                        self.objectWillChange.send()
                        self.clockInTime = clockIn
                        self.clockedOutTime = clockOut
                        self.todayLabel = payload.todayLabel
                        self.isDoneForTheDay = true
                        self.isWorking = false
                        self.isOverTime = false
                        self.targetClockOutTime = nil
                        self.stopTimer?.invalidate()
                        self.nagTimer?.invalidate()
                        NotificationCenter.default.post(name: .sessionStateDidChange, object: nil)
                        done()
                    }
                } else if payload.clockedIn {
                    // Timecard says we're clocked in (not out yet): set state from parsed time or fallback.
                    let clockIn: Date = {
                        if let timeStr = payload.clockInTime, let parsed = Self.today(atTime: timeStr) { return parsed }
                        var fallback = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                        fallback.hour = 8
                        fallback.minute = 54
                        fallback.second = 0
                        return Calendar.current.date(from: fallback) ?? Date()
                    }()
                    AppLogger.verbose("Session: applying clocked-in state, clockIn=\(clockIn)")
                    DispatchQueue.main.async {
                        self.setLastKnownWorkingDay(workingDay)
                        self.objectWillChange.send()
                        self.clockInTime = clockIn
                        self.clockedOutTime = nil
                        self.todayLabel = payload.todayLabel
                        self.isDoneForTheDay = false
                        self.isWorking = true
                        self.isOverTime = false
                        self.scheduleTimers(from: clockIn)
                        AppLogger.verbose("Session: state updated isWorking=true, clockInTime set")
                        NotificationCenter.default.post(name: .sessionStateDidChange, object: nil)
                        done()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.setLastKnownWorkingDay(workingDay)
                        self.objectWillChange.send()
                        self.todayLabel = payload.todayLabel
                        self.isDoneForTheDay = false
                        self.clockedOutTime = nil
                        if self.isWorking {
                            self.isWorking = false
                            self.isOverTime = false
                            self.clockInTime = nil
                            self.targetClockOutTime = nil
                            self.stopTimer?.invalidate()
                            self.nagTimer?.invalidate()
                            NotificationCenter.default.post(name: .sessionStateDidChange, object: nil)
                        }
                        done()
                    }
                }
            case .failure(let err):
                AppLogger.error("Session: timecard fetch failed \(err.localizedDescription)")
                PreflightState.shared.setSiteReachable(false)
                let msg = err.localizedDescription
                DispatchQueue.main.async {
                    self.todayLabel = nil
                    self.pendingStartPromptAfterPreflight = false
                    if self.isNodeNotResolved(err) {
                        self.showNodeNotFoundAlert()
                    } else if msg.contains(AutomationInvoker.loginFailedMessage) || msg.contains(AutomationInvoker.badCredentialsMessage) || msg.contains(AutomationInvoker.loginTimeoutMessage) {
                        self.showLoginFailedAlert(output: msg)
                    } else if msg.contains(AutomationInvoker.networkErrorMessage) || msg.lowercased().contains("timeout") {
                        self.showNetworkErrorAlert()
                    } else {
                        self.showTimecardFetchFailedAlert(reason: msg.isEmpty ? L10n.string("error.try_sync") : msg)
                    }
                    done()
                }
            }
        }
    }

    /// If launch requested start prompt after preflight, check and show now. Call on main after preflight completes.
    private func considerStartPromptAfterPreflight() {
        guard pendingStartPromptAfterPreflight else { return }
        pendingStartPromptAfterPreflight = false
        if shouldShowStartPrompt() {
            showStartWorkPrompt()
        }
    }

    private var stopTimer: Timer?
    private var nagTimer: Timer?

    var statusText: String {
        if isOverTime {
            return L10n.string("status.over_planned")
        } else if isWorking {
            return L10n.string("status.working")
        } else {
            return L10n.string("status.idle")
        }
    }

    /// Rich status for About dialog: working day + clock state (from last time card fetch).
    var aboutStatusText: String {
        if isAutomationRunning {
            return L10n.string("status.fetching")
        }
        if isDoneForTheDay {
            if let working = lastKnownIsWorkingDay, working {
                return L10n.string("status.working_day_done")
            }
            return L10n.string("status.done_for_day")
        }
        let clockState = isWorking ? L10n.string("status.clocked_in") : L10n.string("status.not_clocked_in")
        if let working = lastKnownIsWorkingDay {
            if working {
                return isWorking ? L10n.string("status.working_day_clocked_in") : L10n.string("status.working_day_not_clocked_in")
            } else {
                return isWorking ? L10n.string("status.non_working_day_clocked_in") : L10n.string("status.non_working_day_not_clocked_in")
            }
        }
        return L10n.string("status.day_type_not_fetched", clockState)
    }

    /// True if currently clocked in and elapsed time >= planned workday hours.
    var hasMetNineHours: Bool {
        guard let clockIn = clockInTime else { return false }
        return Date().timeIntervalSince(clockIn) >= AppSettings.shared.workDuration
    }

    /// e.g. "2h 34m" when clocked in, nil otherwise.
    var hoursWorkedText: String? {
        guard let clockIn = clockInTime else { return nil }
        let elapsed = Int(Date().timeIntervalSince(clockIn))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        return L10n.string("status.hours_worked", hours, minutes)
    }

    private init() {
        if let stored = UserDefaults.standard.object(forKey: Self.lastKnownWorkingDayKey) as? Bool {
            lastKnownIsWorkingDay = stored
        }
    }

    private func setLastKnownWorkingDay(_ value: Bool) {
        lastKnownIsWorkingDay = value
        UserDefaults.standard.set(value, forKey: Self.lastKnownWorkingDayKey)
    }

    func handleLaunch() {
        // Timecard is the single source of truth on launch; do not restore from persistence so we never show stale "clocked in" when KOT says otherwise.
        pendingStartPromptAfterPreflight = true
        refreshFromTimeCard()
    }

    /// Re-fetch time card and update state (e.g. after wake). Timecard is the only source of truth.
    func recheckTimecardStatus() {
        refreshFromTimeCard()
    }

    // MARK: - Start/Stop flows

    func startWorkFlow(forcePrompt: Bool) {
        guard CredentialsManager.shared.hasStoredCredentials else { return }
        if forcePrompt || !isWorking {
            showStartWorkPrompt()
        }
    }

    /// Clock in from menu — no dialog; run automation and update state on success. Guard is enforced by automation (time card); on ALREADY_CLOCKED_IN we show alert.
    func clockInFromMenu() {
        guard CredentialsManager.shared.hasStoredCredentials else { return }
        objectWillChange.send()
        isAutomationRunning = true
        AutomationInvoker.shared.runClock(action: .clockIn) { success, output in
            self.isAutomationRunning = false
            if success {
                self.setClockInStateOptimistic()
                self.applyClockInStateFromTimeCard()
            } else {
                DispatchQueue.main.async {
                    if self.isNodeNotResolvedMessage(output) {
                        self.showNodeNotFoundAlert()
                    } else if output.contains(AutomationInvoker.alreadyClockedInMessage) {
                        self.showAlreadyClockedInAlert()
                    } else if output.contains(AutomationInvoker.loginFailedMessage) || output.contains(AutomationInvoker.badCredentialsMessage) || output.contains(AutomationInvoker.loginTimeoutMessage) {
                        self.showLoginFailedAlert(output: output)
                    } else if output.contains(AutomationInvoker.networkErrorMessage) || output.lowercased().contains("timeout") {
                        self.showNetworkErrorAlert()
                    } else {
                        self.showTimecardFetchFailedAlert(reason: output.isEmpty ? L10n.string("error.clock_in_failed") : output)
                    }
                }
            }
        }
    }

    /// Clock out from menu — only show dialog if under 9hr; otherwise run automation and clear state on success. Guard (not clocked in / already clocked out) is enforced by automation.
    func stopWorkFlow() {
        guard CredentialsManager.shared.hasStoredCredentials else { return }
        if hasMetNineHours {
            objectWillChange.send()
            isAutomationRunning = true
            AutomationInvoker.shared.runClock(action: .clockOut) { success, output in
                self.isAutomationRunning = false
                if success {
                    self.clearStateAndPersist()
                } else {
                    DispatchQueue.main.async {
                        if self.isNodeNotResolvedMessage(output) {
                            self.showNodeNotFoundAlert()
                        } else if output.contains(AutomationInvoker.notClockedInMessage) || output.contains(AutomationInvoker.alreadyClockedOutMessage) {
                            self.showGuardClockOutAlert(output: output)
                        } else if output.contains(AutomationInvoker.loginFailedMessage) || output.contains(AutomationInvoker.badCredentialsMessage) || output.contains(AutomationInvoker.loginTimeoutMessage) {
                            self.showLoginFailedAlert(output: output)
                        } else if output.contains(AutomationInvoker.networkErrorMessage) || output.lowercased().contains("timeout") {
                            self.showNetworkErrorAlert()
                        } else {
                            self.showTimecardFetchFailedAlert(reason: output.isEmpty ? L10n.string("error.clock_out_failed") : output)
                        }
                    }
                }
            }
        } else {
            showStopWorkPrompt(force: true)
        }
    }

    // MARK: - Prompts

    private func shouldShowStartPrompt() -> Bool {
        if isWorking || isDoneForTheDay { return false }
        if lastKnownIsWorkingDay == false { return false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let stored = UserDefaults.standard.object(forKey: Self.dontAskAgainKey) as? Date {
            let storedDay = calendar.startOfDay(for: stored)
            if storedDay == today {
                return false
            }
        }

        return true
    }

    private func markDontAskAgainToday() {
        let today = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(today, forKey: Self.dontAskAgainKey)
    }

    private func showAlreadyClockedInAlert() {
        AlreadyClockedInPromptPresenter.present(onDismiss: {})
    }

    private func showGuardClockOutAlert(output: String) {
        let message = output.contains(AutomationInvoker.notClockedInMessage)
            ? L10n.string("alert.cannot_clock_out.not_clocked_in")
            : L10n.string("alert.cannot_clock_out.already_clocked_out")
        CannotClockOutPromptPresenter.present(message: message, onDismiss: {})
    }

    private func loginFailedMessage(from output: String) -> String {
        if output.contains(AutomationInvoker.badCredentialsMessage) {
            return L10n.string("alert.login_failed.bad_credentials")
        }
        if output.contains(AutomationInvoker.loginTimeoutMessage) {
            return L10n.string("alert.login_failed.timeout")
        }
        return L10n.string("alert.login_failed.message")
    }

    func showLoginFailedAlert(output: String = "") {
        let message = loginFailedMessage(from: output)
        LoginFailedPromptPresenter.present(message: message, onDismiss: {
            SettingsWindowController.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: .settingsFocusCredentialsField, object: nil)
            }
        })
    }

    /// Offline (no internet): own dialog; dismiss does NOT open Settings — user can't fix connectivity there.
    func showNetworkOfflineAlert() {
        NetworkOfflinePromptPresenter.present()
    }

    /// Site unreachable (bad URL, host down, etc.): prompt; dismiss opens Settings and focuses URL.
    func showCannotReachSiteAlert() {
        CannotReachSitePromptPresenter.present(onDismiss: {
            SettingsWindowController.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(name: .settingsFocusURLField, object: nil)
            }
        })
    }

    /// Route to offline vs cannot-reach-site dialog based on connectivity; only one opens Settings on dismiss.
    private func showNetworkErrorAlert() {
        if !PreflightState.shared.networkConnected {
            showNetworkOfflineAlert()
        } else {
            showCannotReachSiteAlert()
        }
    }

    private static let nodeNotResolvedErrorKind = "node_not_resolved"

    private func isNodeNotResolved(_ error: Error) -> Bool {
        (error as NSError).userInfo["JOTErrorKind"] as? String == Self.nodeNotResolvedErrorKind
    }

    private func isNodeNotResolvedMessage(_ message: String) -> Bool {
        message == L10n.string("error.node_not_resolved")
    }

    func showNodeNotFoundAlert() {
        NodeNotFoundPromptPresenter.present(onDismiss: {})
    }

    // MARK: - Local-only test alerts

    /// Kinds of alerts that can be shown from the Develop menu for testing. Only honored when `AppEnvironment.isLocal`.
    enum TestAlertKind: String, CaseIterable {
        case networkOffline
        case cannotReachSite
        case nodeNotFound
        case loginFailed
        case somethingWrong
        case alreadyClockedIn
        case guardClockOutNotClockedIn
        case guardClockOutAlreadyClockedOut
        case startWorkPrompt
        /// Clock-out dialog when under planned hours (e.g. "Clock out now? … about 1h 0m remaining").
        case stopWorkEarlyPrompt
        /// Clock-out dialog when workday time is just met ("You have reached your planned work limit").
        case stopWorkMetLimitPrompt
        /// Clock-out dialog when over planned hours / 15 min nag ("You are 0h 15m over...").
        case stopWorkOverLimitPrompt
    }

    /// Show a specific alert for testing. No-op when not in local environment.
    func showTestAlert(_ kind: TestAlertKind) {
        guard AppEnvironment.isLocal else { return }
        switch kind {
        case .networkOffline: showNetworkOfflineAlert()
        case .cannotReachSite: showCannotReachSiteAlert()
        case .nodeNotFound: showNodeNotFoundAlert()
        case .loginFailed: showLoginFailedAlert()
        case .somethingWrong: showTimecardFetchFailedAlert(reason: "Test")
        case .alreadyClockedIn: showAlreadyClockedInAlert()
        case .guardClockOutNotClockedIn: showGuardClockOutAlert(output: AutomationInvoker.notClockedInMessage)
        case .guardClockOutAlreadyClockedOut: showGuardClockOutAlert(output: AutomationInvoker.alreadyClockedOutMessage)
        case .startWorkPrompt: showStartWorkPrompt()
        case .stopWorkEarlyPrompt: showTestStopWorkPrompt(variant: .early)
        case .stopWorkMetLimitPrompt: showTestStopWorkPrompt(variant: .metLimit)
        case .stopWorkOverLimitPrompt: showTestStopWorkPrompt(variant: .overLimit)
        }
    }

    /// Local-only: present the Stop Work dialog (same component as real flow) with sample text for testing.
    private enum StopWorkTestVariant {
        case early      // Before work day done (under planned hours)
        case metLimit  // When workday time is met
        case overLimit // Overtime / 15 min nag after exceeding
    }

    private func showTestStopWorkPrompt(variant: StopWorkTestVariant) {
        guard AppEnvironment.isLocal else { return }
        let title: String
        let message: String
        let isCritical: Bool
        switch variant {
        case .early:
            title = L10n.string("stop_work.early.title")
            message = L10n.string("stop_work.early.message", 1, 0)
            isCritical = false
        case .metLimit:
            title = L10n.string("stop_work.critical.title")
            message = L10n.string("stop_work.critical.message")
            isCritical = true
        case .overLimit:
            title = L10n.string("stop_work.critical.title")
            message = L10n.string("stop_work.over.message", 0, 15)
            isCritical = true
        }
        let isOverLimit = (variant == .overLimit)
        StopWorkPromptPresenter.present(
            title: title,
            message: message,
            isCritical: isCritical,
            isOverLimit: isOverLimit,
            onYes: {},
            onNo: {}
        )
    }

    private func showSomethingWentWrongAlert() {
        SomethingWentWrongPromptPresenter.present(onDismiss: {})
    }

    private func showTimecardFetchFailedAlert(reason: String) {
        showSomethingWentWrongAlert()
    }

    /// Show alert only; no Settings on dismiss (e.g. network offline — user can't fix that in Settings).
    private func showAlertOnly(title: String, message: String) {
        let alert = NSAlert()
        let appName = L10n.string("window.title")
        alert.messageText = "\(appName) — \(title)"
        alert.informativeText = message
        alert.alertStyle = .warning
        if #available(macOS 11.0, *) {
            alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: L10n.string("alert.error_icon"))
        }
        alert.addButton(withTitle: L10n.string("alert.ok"))
        alert.window.level = .statusBar
        alert.window.makeKeyAndOrderFront(nil)
        alert.window.center()
        alert.runModal()
    }

    private func showStartWorkPrompt() {
        StartWorkPromptPresenter.present(
            onYes: { [weak self] in
                AppLogger.info("User: Start Work — Yes")
                guard let self else { return }
                StatusItemManager.lastModalDismissTime = Date()
                if self.isWorking {
                    AppLogger.debug("Session: already clocked in today, skipping duplicate clock-in")
                    return
                }
                self.objectWillChange.send()
                self.isAutomationRunning = true
                AutomationInvoker.shared.runClock(action: .clockIn) { success, output in
                    self.isAutomationRunning = false
                    if success {
                        self.setClockInStateOptimistic()
                        self.applyClockInStateFromTimeCard()
                    } else {
                        DispatchQueue.main.async {
                            if self.isNodeNotResolvedMessage(output) {
                                self.showNodeNotFoundAlert()
                            } else if output.contains(AutomationInvoker.alreadyClockedInMessage) {
                                self.showAlreadyClockedInAlert()
                            } else if output.contains(AutomationInvoker.loginFailedMessage) || output.contains(AutomationInvoker.badCredentialsMessage) || output.contains(AutomationInvoker.loginTimeoutMessage) {
                                self.showLoginFailedAlert(output: output)
                            } else if output.contains(AutomationInvoker.networkErrorMessage) || output.lowercased().contains("timeout") {
                                self.showNetworkErrorAlert()
                            } else {
                                self.showTimecardFetchFailedAlert(reason: output.isEmpty ? L10n.string("error.clock_in_failed") : output)
                            }
                        }
                    }
                }
            },
            onNo: { [weak self] dontAskAgain in
                AppLogger.info("User: Start Work — No, dontAskAgain=\(dontAskAgain)")
                guard let self else { return }
                StatusItemManager.lastModalDismissTime = Date()
                if dontAskAgain {
                    self.markDontAskAgainToday()
                } else {
                    self.scheduleRePrompt()
                }
            }
        )
    }

    /// Sync timecard first; only show stop-work dialog if we're still clocked in (avoid sending clock-out when not on the clock).
    private func showStopWorkPrompt(force: Bool) {
        AutomationInvoker.shared.runTimecardStatus { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let payload):
                if payload.clockedOut {
                    AppLogger.debug("Session: stop-work timecard says already clocked out — updating state, not showing dialog")
                    self.applyTimecardPayloadNotClockedIn(payload)
                    return
                }
                if !payload.clockedIn {
                    AppLogger.debug("Session: stop-work timecard says not clocked in — updating state, not showing dialog")
                    self.applyTimecardPayloadNotClockedIn(payload)
                    return
                }
                // Use server clock-in time for the dialog so "Xh Ym over" is accurate
                if let timeStr = payload.clockInTime, let clockIn = Self.today(atTime: timeStr) {
                    DispatchQueue.main.async {
                        self.clockInTime = clockIn
                        self.showStopWorkPromptAfterSync(force: force)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showStopWorkPromptAfterSync(force: force)
                    }
                }
            case .failure(let err):
                AppLogger.error("Session: stop-work timecard sync failed \(err.localizedDescription), not showing dialog")
                let msg = err.localizedDescription
                DispatchQueue.main.async {
                    if self.isNodeNotResolved(err) {
                        self.showNodeNotFoundAlert()
                    } else if msg.contains(AutomationInvoker.loginFailedMessage) || msg.contains(AutomationInvoker.badCredentialsMessage) || msg.contains(AutomationInvoker.loginTimeoutMessage) {
                        self.showLoginFailedAlert(output: msg)
                    } else if msg.contains(AutomationInvoker.networkErrorMessage) || msg.lowercased().contains("timeout") {
                        self.showNetworkErrorAlert()
                    } else {
                        self.showTimecardFetchFailedAlert(reason: msg.isEmpty ? L10n.string("error.try_sync") : msg)
                    }
                }
            }
        }
    }

    /// Apply timecard payload when we're done for the day or not clocked in (so we don't show clock-out dialog).
    private func applyTimecardPayloadNotClockedIn(_ payload: TimecardStatusPayload) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setLastKnownWorkingDay(payload.shouldWorkToday)
            self.objectWillChange.send()
            if payload.clockedOut {
                self.clockInTime = payload.clockInTime.flatMap { Self.today(atTime: $0) }
                self.clockedOutTime = payload.clockOutTime.flatMap { Self.today(atTime: $0) }
                self.isDoneForTheDay = true
            } else {
                self.clockInTime = nil
                self.clockedOutTime = nil
                self.isDoneForTheDay = false
            }
            self.isWorking = false
            self.isOverTime = false
            self.targetClockOutTime = nil
            self.stopTimer?.invalidate()
            self.nagTimer?.invalidate()
            NotificationCenter.default.post(name: .sessionStateDidChange, object: nil)
        }
    }

    private func showStopWorkPromptAfterSync(force: Bool) {
        let nineHours: TimeInterval = AppSettings.shared.workDuration
        var hasMetNineHours = false
        var isOverLimit = false
        let title: String
        let message: String
        if let clockIn = clockInTime {
            let elapsed = Date().timeIntervalSince(clockIn)
            hasMetNineHours = elapsed >= nineHours
            isOverLimit = hasMetNineHours && (elapsed - nineHours) > 0
            if hasMetNineHours {
                title = L10n.string("stop_work.critical.title")
                let over = max(0, elapsed - nineHours)
                let hours = Int(over) / 3600
                let minutes = (Int(over) % 3600) / 60
                message = L10n.string("stop_work.over.message", hours, minutes)
            } else {
                let remaining = nineHours - elapsed
                let hours = Int(remaining) / 3600
                let minutes = (Int(remaining) % 3600) / 60
                title = L10n.string("stop_work.early.title")
                message = L10n.string("stop_work.early.message", hours, minutes)
            }
        } else {
            title = L10n.string("stop_work.confirm.title")
            message = L10n.string("stop_work.confirm.message")
        }

        StopWorkPromptPresenter.present(
            title: title,
            message: message,
            isCritical: hasMetNineHours,
            isOverLimit: isOverLimit,
            onYes: { [weak self] in
                AppLogger.info("User: Stop Work — Yes, clock out")
                StatusItemManager.lastModalDismissTime = Date()
                guard let self else { return }
                self.objectWillChange.send()
                self.isAutomationRunning = true
                AutomationInvoker.shared.runClock(action: .clockOut) { success, output in
                    self.isAutomationRunning = false
                    if success {
                        self.clearStateAndPersist()
                    } else {
                        DispatchQueue.main.async {
                            if self.isNodeNotResolvedMessage(output) {
                                self.showNodeNotFoundAlert()
                            } else if output.contains(AutomationInvoker.notClockedInMessage) || output.contains(AutomationInvoker.alreadyClockedOutMessage) {
                                self.showGuardClockOutAlert(output: output)
                            } else if output.contains(AutomationInvoker.loginFailedMessage) || output.contains(AutomationInvoker.badCredentialsMessage) || output.contains(AutomationInvoker.loginTimeoutMessage) {
                                self.showLoginFailedAlert(output: output)
                            } else if output.contains(AutomationInvoker.networkErrorMessage) || output.lowercased().contains("timeout") {
                                self.showNetworkErrorAlert()
                            } else {
                                self.showTimecardFetchFailedAlert(reason: output.isEmpty ? L10n.string("error.clock_out_failed") : output)
                            }
                        }
                    }
                }
            },
            onNo: { [weak self] in
                AppLogger.info("User: Stop Work — No, keep working")
                StatusItemManager.lastModalDismissTime = Date()
                guard let self else { return }
                if hasMetNineHours {
                    self.isOverTime = true
                    if force {
                        self.scheduleNag()
                    }
                }
            }
        )
    }

    // MARK: - Timers

    /// Call when workday hours setting changes so the stop/nag timers use the new duration. No-op if not clocked in.
    func rescheduleTimersIfClockedIn() {
        guard isWorking, let clockIn = clockInTime else { return }
        scheduleTimers(from: clockIn)
    }

    private func scheduleTimers(from clockIn: Date) {
        stopTimer?.invalidate()
        nagTimer?.invalidate()

        let nineHours: TimeInterval = AppSettings.shared.workDuration
        let target = clockIn.addingTimeInterval(nineHours)
        targetClockOutTime = target

        let interval = target.timeIntervalSinceNow
        if interval <= 0 {
            // Already past, show stop prompt soon.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showStopWorkPrompt(force: true)
            }
        } else {
            stopTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.showStopWorkPrompt(force: true)
            }
        }
    }

    private func scheduleNag() {
        nagTimer?.invalidate()
        nagTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.showStopWorkPrompt(force: true)
        }
    }

    private func scheduleRePrompt() {
        // Ask again in 15 minutes if user said No without "don't ask again".
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !self.isWorking && self.shouldShowStartPrompt() {
                self.showStartWorkPrompt()
            }
        }
    }

    // MARK: - Helpers

    /// Build a Date for today at the given time string (e.g. "08:54"). Returns nil if parsing fails.
    private static func today(atTime timeString: String) -> Date? {
        let parts = timeString.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)
    }

    /// Set clocked-in state immediately so the menu icon updates; timecard fetch will replace with server time when it completes.
    private func setClockInStateOptimistic() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            let now = Date()
            self.clockInTime = now
            self.clockedOutTime = nil
            self.isDoneForTheDay = false
            self.isWorking = true
            self.isOverTime = false
            self.scheduleTimers(from: now)
        }
    }

    /// Fetch time card and apply clock-in state from KOT (workday basis). Call after clock-in automation succeeds.
    private func applyClockInStateFromTimeCard() {
        AutomationInvoker.shared.runTimecardStatus { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let payload):
                guard payload.clockedIn, let timeStr = payload.clockInTime,
                      let clockIn = Self.today(atTime: timeStr) else {
                    self.applyClockInStateFallback()
                    return
                }
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.clockInTime = clockIn
                    self.clockedOutTime = nil
                    self.isDoneForTheDay = false
                    self.isWorking = true
                    self.isOverTime = false
                    self.scheduleTimers(from: clockIn)
                }
            case .failure:
                self.applyClockInStateFallback()
            }
        }
    }

    /// Fallback when time card fetch fails after clock-in: use current time so UI still updates.
    private func applyClockInStateFallback() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            let now = Date()
            self.clockInTime = now
            self.clockedOutTime = nil
            self.isDoneForTheDay = false
            self.isWorking = true
            self.isOverTime = false
            self.scheduleTimers(from: now)
        }
    }

    /// Apply clock-in state after automation has completed successfully. Do not call before automation succeeds. (Legacy; prefer applyClockInStateFromTimeCard for workday basis from KOT.)
    private func applyClockInState() {
        objectWillChange.send()
        let now = Date()
        clockInTime = now
        isWorking = true
        isOverTime = false
        scheduleTimers(from: now)
    }

    /// Clear session state after clock-out automation has completed successfully. Do not call before automation succeeds.
    private func clearStateAndPersist() {
        objectWillChange.send()
        let outTime = Date()
        clockedOutTime = outTime
        isDoneForTheDay = true
        isWorking = false
        isOverTime = false
        clockInTime = nil
        targetClockOutTime = nil
        stopTimer?.invalidate()
        nagTimer?.invalidate()
        NotificationCenter.default.post(name: .sessionStateDidChange, object: nil)
        AppLogger.info("Session: clocked out, done for the day")
    }

    /// Call when credentials were just saved (new or updated). Clears session state and stops the automation daemon so the next run uses a fresh daemon with the new account.
    func clearSessionStateForNewCredentials() {
        AutomationInvoker.shared.stopDaemon()
        objectWillChange.send()
        pendingStartPromptAfterPreflight = true
        isWorking = false
        isOverTime = false
        isDoneForTheDay = false
        clockInTime = nil
        clockedOutTime = nil
        targetClockOutTime = nil
        stopTimer?.invalidate()
        nagTimer?.invalidate()
        UserDefaults.standard.removeObject(forKey: Self.dontAskAgainKey)
        AppLogger.info("Session: credentials changed — state cleared, daemon stopped, will re-fetch time card")
    }

    /// Call when credentials are cleared: stop daemon, clear all session state, close any clock-in/clock-out prompts. No automation runs.
    func onCredentialsCleared() {
        AutomationInvoker.shared.stopDaemon()
        objectWillChange.send()
        pendingStartPromptAfterPreflight = false
        isWorking = false
        isOverTime = false
        isDoneForTheDay = false
        clockInTime = nil
        clockedOutTime = nil
        targetClockOutTime = nil
        stopTimer?.invalidate()
        nagTimer?.invalidate()
        UserDefaults.standard.removeObject(forKey: Self.dontAskAgainKey)
        StartWorkPromptPresenter.closeIfOpen()
        StopWorkPromptPresenter.closeIfOpen()
        AppLogger.info("Session: credentials cleared — daemon stopped, state reset, prompts closed")
    }

}
