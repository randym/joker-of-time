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
                DispatchQueue.main.async {
                    self.todayLabel = nil
                    self.pendingStartPromptAfterPreflight = false
                    self.routeTimecardStatusError(err, defaultErrorKey: "error.try_sync")
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
        setupPromptObservers()
    }
    
    private func setupPromptObservers() {
        NotificationCenter.default.addObserver(
            forName: .promptStartWorkClockIn,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleStartWorkClockIn()
        }
        
        NotificationCenter.default.addObserver(
            forName: .promptStartWorkDismiss,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleStartWorkDismiss()
        }
        
        NotificationCenter.default.addObserver(
            forName: .promptStopWorkClockOut,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleStopWorkClockOut()
        }
        
        NotificationCenter.default.addObserver(
            forName: .promptStopWorkKeepWorking,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleStopWorkKeepWorking(note: note)
        }
        
        NotificationCenter.default.addObserver(
            forName: .promptCredentialsRequiredGoToSettings,
            object: nil,
            queue: .main
        ) { _ in
            SettingsWindowController.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: .settingsFocusCredentialsField, object: nil)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .promptLoginFailedDismiss,
            object: nil,
            queue: .main
        ) { _ in
            SettingsWindowController.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: .settingsFocusCredentialsField, object: nil)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .promptNodeNotFoundDismiss,
            object: nil,
            queue: .main
        ) { _ in
            // Only open Settings in dev builds (nodePath is only configurable in dev)
            if AppEnvironment.isLocal {
                SettingsWindowController.shared.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .settingsFocusNodePathField, object: nil)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .promptCannotReachSiteDismiss,
            object: nil,
            queue: .main
        ) { _ in
            SettingsWindowController.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(name: .settingsFocusURLField, object: nil)
            }
        }
    }
    
    private func handleStartWorkClockIn() {
        AppLogger.info("User: Start Work — Yes")
        StatusItemManager.lastModalDismissTime = Date()
        if isWorking {
            AppLogger.debug("Session: already clocked in today, skipping duplicate clock-in")
            return
        }
        objectWillChange.send()
        AutomationController.shared.requestClockIn()
    }
    
    private func handleStartWorkDismiss() {
        AppLogger.info("User: Start Work — No")
        StatusItemManager.lastModalDismissTime = Date()
        scheduleRePrompt()
    }
    
    private func handleStopWorkClockOut() {
        AppLogger.info("User: Stop Work — Yes, clock out")
        StatusItemManager.lastModalDismissTime = Date()
        objectWillChange.send()
        AutomationController.shared.requestClockOut()
    }
    
    private func handleStopWorkKeepWorking(note: Notification) {
        AppLogger.info("User: Stop Work — No, keep working")
        StatusItemManager.lastModalDismissTime = Date()
        // Calculate hasMetNineHours from current state
        let nineHours: TimeInterval = AppSettings.shared.workDuration
        if let clockIn = clockInTime {
            let elapsed = Date().timeIntervalSince(clockIn)
            let hasMetNineHours = elapsed >= nineHours
            if hasMetNineHours {
                isOverTime = true
                scheduleNag()
            }
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
        if forcePrompt || !isWorking {
            showStartWorkPrompt()
        }
    }

    /// Clock in from menu — no dialog; run automation and update state on success. Guard is enforced by automation (time card); on ALREADY_CLOCKED_IN we show alert.
    func clockInFromMenu() {
        objectWillChange.send()
        AutomationController.shared.requestClockIn()
    }

    /// Clock out from menu — only show dialog if under 9hr; otherwise run automation and clear state on success. Guard (not clocked in / already clocked out) is enforced by automation.
    func stopWorkFlow() {
        if hasMetNineHours {
            objectWillChange.send()
            AutomationController.shared.requestClockOut()
        } else {
            showStopWorkPrompt(force: true)
        }
    }

    // MARK: - Prompts

    private func shouldShowStartPrompt() -> Bool {
        if isWorking || isDoneForTheDay { return false }
        if lastKnownIsWorkingDay == false { return false }

        return true
    }

    private func showAlreadyClockedInAlert() {
        AlreadyClockedIn.present()
    }

    private func showGuardClockOutAlert(output: String) {
        if output.contains(AutomationInvoker.notClockedInMessage) {
            NotClockedIn.present()
        } else if output.contains(AutomationInvoker.alreadyClockedOutMessage) {
            AlreadyClockedOut.present()
        } else {
            CannotClockOut.present()
        }
    }


    // MARK: - Automation success/failure helpers (Clock In/Out)

    func onClockInAutomationSucceeded() {
        setClockInStateOptimistic()
        applyClockInStateFromTimeCard()
    }

    func onClockInAutomationFailed(output: String) {
        routeAutomationErrorMessage(
            message: output,
            defaultErrorKey: "error.clock_in_failed",
            context: .clockIn
        )
    }

    func onClockOutAutomationSucceeded() {
        clearStateAndPersist()
    }

    func onClockOutAutomationFailed(output: String) {
        routeAutomationErrorMessage(
            message: output,
            defaultErrorKey: "error.clock_out_failed",
            context: .clockOut
        )
    }
    /// Shared mapper from timecard-status errors (errors fetching timecard before dialogs) to the appropriate UI.
    /// Caller must already be on the main queue when invoking this.
    private func routeTimecardStatusError(_ error: Error, defaultErrorKey: String = "error.try_sync") {
        if let automationFailure = error as? AutomationFailure {
            routeAutomationErrorMessage(
                message: automationFailure.code.rawValue,
                defaultErrorKey: defaultErrorKey,
                context: .timecardStatus
            )
        } else {
            let msg = error.localizedDescription
            routeAutomationErrorMessage(message: msg, defaultErrorKey: defaultErrorKey, context: .timecardStatus)
        }
    }

    private enum AutomationErrorContext {
        case timecardStatus
        case clockIn
        case clockOut
    }

    /// Shared mapper from automation errors (timecard-status or clock-in/out) to the appropriate UI.
    /// Handlers are applied in order (guard → login → network → generic), and each is a no-op
    /// when its pattern does not match.
    private func routeAutomationErrorMessage(
        message: String,
        defaultErrorKey: String,
        context: AutomationErrorContext
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if self.handleGuardErrorIfNeeded(message, in: context) { return }
            if self.handleLoginErrorIfNeeded(message) { return }
            if self.handleNetworkErrorIfNeeded(message) { return }

            let fallback = L10n.string(defaultErrorKey)
            self.showTimecardFetchFailedAlert(reason: message.isEmpty ? fallback : message)
        }
    }

    /// Handle guard-style failures (already clocked in / not clocked in / already clocked out).
    /// Returns true if the message was handled, false otherwise.
    private func handleGuardErrorIfNeeded(_ message: String, in context: AutomationErrorContext) -> Bool {
        switch context {
        case .clockIn:
            if message.contains(AutomationInvoker.alreadyClockedInMessage) {
                showAlreadyClockedInAlert()
                return true
            }
            return false
        case .clockOut:
            if message.contains(AutomationInvoker.notClockedInMessage) {
                NotClockedIn.present()
                return true
            }
            if message.contains(AutomationInvoker.alreadyClockedOutMessage) {
                AlreadyClockedOut.present()
                return true
            }
            return false
        case .timecardStatus:
            return false
        }
    }

    /// Handle login failures; returns true if handled.
    private func handleLoginErrorIfNeeded(_ message: String) -> Bool {
        let isLoginError =
            message.contains(AutomationInvoker.loginFailedMessage) ||
            message.contains(AutomationInvoker.badCredentialsMessage) ||
            message.contains(AutomationInvoker.loginTimeoutMessage)
        if isLoginError {
            showLoginFailedAlert(output: message)
            return true
        }
        return false
    }

    /// Handle network-related failures; returns true if handled.
    private func handleNetworkErrorIfNeeded(_ message: String) -> Bool {
        let isNetworkError =
            message.contains(AutomationInvoker.networkErrorMessage) ||
            message.lowercased().contains("timeout")
        if isNetworkError {
            showNetworkErrorAlert()
            return true
        }
        return false
    }

    func showCredentialsRequiredAlert() {
        CredentialsRequired.present()
    }

    func showLoginFailedAlert(output: String = "") {
        LoginFailed.present()
    }

    /// Offline (no internet): own dialog; dismiss does NOT open Settings — user can't fix connectivity there.
    func showNetworkOfflineAlert() {
        NetworkOffline.present()
    }

    /// Site unreachable (bad URL, host down, etc.): prompt; dismiss opens Settings and focuses URL.
    func showCannotReachSiteAlert() {
        CannotReachSite.present()
    }

    /// Route to offline vs cannot-reach-site dialog based on connectivity; only one opens Settings on dismiss.
    private func showNetworkErrorAlert() {
        if !PreflightState.shared.networkConnected {
            showNetworkOfflineAlert()
        } else {
            showCannotReachSiteAlert()
        }
    }

    func showNodeNotFoundAlert() {
        NodeNotFound.present()
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
        case .guardClockOutNotClockedIn: NotClockedIn.present()
        case .guardClockOutAlreadyClockedOut: AlreadyClockedOut.present()
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
        switch variant {
        case .early:
            StopWorkEarly.present()
        case .metLimit:
            StopWorkOnTime.present()
        case .overLimit:
            StopWorkLate.present()
        }
    }

    private func showSomethingWentWrongAlert() {
        SomethingWentWrong.present()
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
        StartWork.present()
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
                DispatchQueue.main.async {
                    self.routeTimecardStatusError(err, defaultErrorKey: "error.try_sync")
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
        if let clockIn = clockInTime {
            let elapsed = Date().timeIntervalSince(clockIn)
            hasMetNineHours = elapsed >= nineHours
            isOverLimit = hasMetNineHours && (elapsed - nineHours) > 0
        }

        if isOverLimit {
            StopWorkLate.present()
        } else if hasMetNineHours {
            StopWorkOnTime.present()
        } else {
            StopWorkEarly.present()
        }
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
        // Ask again in 15 minutes if user said No.
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
        PromptPresenter.closeIfOpen()
        AppLogger.info("Session: credentials cleared — daemon stopped, state reset, prompts closed")
    }

}
