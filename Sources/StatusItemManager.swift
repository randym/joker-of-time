import AppKit
import SwiftUI

/// Owns the menu bar status item and its normal dropdown menu. Updates the status item's image from SessionManager.
final class StatusItemManager: NSObject {
    static let shared = StatusItemManager()

    /// After a modal alert is dismissed, the mouse-up can hit the status item. Ignore opens for this long.
    static let modalDismissGraceInterval: TimeInterval = 0.4
    static var lastModalDismissTime: Date?

    private var statusItem: NSStatusItem?
    private var iconUpdateTimer: Timer?
    private var spinnerTimer: Timer?
    private var spinnerAngle: Double = 0
    private var lastIconStateKey: String = ""

    private static let iconSize: CGFloat = 18

    private override init() {
        super.init()
    }

    func setup() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        button.action = #selector(showMenuOrCredentials)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateIcon(force: true)
        startIconUpdateTimer()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshIconFromNotification), name: .sessionStateDidChange, object: nil)
    }

    @objc private func refreshIconFromNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.updateIcon(force: true)
        }
    }

    private func startIconUpdateTimer() {
        iconUpdateTimer?.invalidate()
        iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateIcon(force: false)
        }
        iconUpdateTimer?.tolerance = 0.05
        RunLoop.main.add(iconUpdateTimer!, forMode: .common)
    }

    /// Resolved status for the menu bar: not ready (with reason) beats spinner beats working/idle. Call on main.
    private enum ResolvedStatus {
        case notReady(reasonKey: String?, iconName: String?)
        case syncing
        case working
        case idle
    }

    /// Read SessionManager + PreflightState → one resolved status. Not-ready wins over spinner so we show the right icon when a fetch fails and the alert pops.
    private static func resolveStatus() -> ResolvedStatus {
        let preflight = PreflightState.shared
        let session = SessionManager.shared
        if !preflight.canRunAutomation {
            return .notReady(reasonKey: preflight.notReadyReasonKey, iconName: preflight.notReadyIconName)
        }
        if session.isAutomationRunning {
            return .syncing
        }
        return session.isWorking ? .working : .idle
    }

    /// Map resolved status to SF Symbol name and accessibility description. Not-ready uses preflight’s concrete icon/reason (no mapping here).
    private static func iconForStatus(_ status: ResolvedStatus) -> (symbolName: String, accessibilityDescription: String) {
        switch status {
        case .notReady(reasonKey: _, iconName: let iconName):
            return (iconName ?? "circle.slash", L10n.string("status.not_ready"))
        case .syncing:
            return (progressIndicatorSymbolName, L10n.string("status.syncing"))
        case .working:
            return ("clock.fill", L10n.string("status.working"))
        case .idle:
            return ("clock", L10n.string("status.idle"))
        }
    }

    /// Read SessionManager, PreflightState and set status item image. Call on main.
    private func updateIcon(force: Bool) {
        let status = Self.resolveStatus()
        let stateKey = "\(status)"
        if !force && stateKey == lastIconStateKey { return }
        lastIconStateKey = stateKey

        switch status {
        case .syncing:
            startSpinnerTimer()
            tickSpinner()
            return
        default:
            stopSpinnerTimer()
            guard let button = statusItem?.button else { return }
            let (symbolName, desc) = Self.iconForStatus(status)
            button.image = Self.templateImage(systemSymbolName: symbolName, size: Self.iconSize, accessibilityDescription: desc)

            // Tooltip: concise summary including today's span/status.
            let session = SessionManager.shared
            let todayBase = Self.todaySummaryBase(session: session)
            let todayText = String(format: L10n.string("menu.today_label"), todayBase)
            let appName = L10n.string("window.title")
            button.toolTip = "\(appName) — \(todayText)"
        }
    }

    /// Human-readable summary for today's status/span, based on SessionManager state.
    private static func todaySummaryBase(session: SessionManager) -> String {
        // If automation hasn't run yet, we may not know anything meaningful.
        if session.isAutomationRunning {
            return L10n.string("status.fetching")
        }

        let isWorkingDay = session.lastKnownIsWorkingDay ?? false
        let hasClockIn = session.clockInTime != nil
        let hasClockOut = session.clockedOutTime != nil

        // Case 3: we have both in/out times (finished for the day).
        if let start = session.clockInTime, let end = session.clockedOutTime {
            let startStr = start.formatted(date: .omitted, time: .shortened)
            let endStr = end.formatted(date: .omitted, time: .shortened)
            return "\(startStr) – \(endStr)"
        }

        // Case 2: clocked in but not out yet — show recommended end based on configured workDuration.
        if let start = session.clockInTime, session.isWorking, !session.isDoneForTheDay {
            let startStr = start.formatted(date: .omitted, time: .shortened)
            let recommended = start.addingTimeInterval(AppSettings.shared.workDuration)
            let endStr = recommended.formatted(date: .omitted, time: .shortened)
            let estSuffix = L10n.string("status.today_est_suffix")
            return "\(startStr) – \(endStr)（\(estSuffix)）"
        }

        // Case 1: working day, not clocked in at all.
        if isWorkingDay, !hasClockIn, !hasClockOut, !session.isWorking, !session.isDoneForTheDay {
            return L10n.string("status.today_not_clocked_in")
        }

        // Case 4: non-working day and not logged in.
        if !isWorkingDay, !hasClockIn, !hasClockOut, !session.isWorking, !session.isDoneForTheDay {
            return L10n.string("status.today_non_working")
        }

        // Fallback: show whatever raw label automation provided, or a dash.
        if let raw = session.todayLabel, !raw.isEmpty {
            return raw
        }
        return "—"
    }

    private func startSpinnerTimer() {
        guard spinnerTimer == nil else { return }
        spinnerAngle = 0
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.tickSpinner()
        }
        spinnerTimer?.tolerance = 0.01
        RunLoop.main.add(spinnerTimer!, forMode: .common)
        tickSpinner()
    }

    private func stopSpinnerTimer() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
    }

    private static let progressIndicatorSymbolName = "progress.indicator"

    private func tickSpinner() {
        guard statusItem?.button != nil, SessionManager.shared.isAutomationRunning else {
            stopSpinnerTimer()
            return
        }
        let angleRad = spinnerAngle * .pi / 180
        spinnerAngle += 7
        if spinnerAngle >= 360 { spinnerAngle -= 360 }
        statusItem?.button?.image = Self.progressIndicatorImage(angleRadians: angleRad)
    }

    /// SF Symbol progress.indicator (or fallback) drawn at rotation for automation-running state.
    private static func progressIndicatorImage(angleRadians: Double) -> NSImage? {
        let name = NSImage(systemSymbolName: progressIndicatorSymbolName, accessibilityDescription: nil) != nil
           ? progressIndicatorSymbolName
            : "arrow.triangle.2.circlepath"
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: L10n.string("status.syncing")) else { return nil }
        source.isTemplate = true
        let size = iconSize
        let image = NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = true
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        let mid = size / 2
        ctx.translateBy(x: mid, y: mid)
        ctx.rotate(by: CGFloat(angleRadians))
        ctx.translateBy(x: -mid, y: -mid)
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        return image
    }

    /// All status icons at a consistent size (template for menu bar).
    private static func templateImage(systemSymbolName: String, size: CGFloat, accessibilityDescription: String?) -> NSImage? {
        guard let source = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityDescription) else { return nil }
        source.isTemplate = true
        let image = NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = true
        image.lockFocus()
        defer { image.unlockFocus() }
        guard NSGraphicsContext.current != nil else { return image }
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        return image
    }

    /// No-op for compatibility (normal menu dismisses on its own).
    func closePopover() {}

    @objc private func showMenuOrCredentials() {
        guard let button = statusItem?.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp { return }
        if let t = StatusItemManager.lastModalDismissTime, Date().timeIntervalSince(t) < StatusItemManager.modalDismissGraceInterval {
            return
        }
        if !CredentialsManager.shared.hasStoredCredentials {
            CredentialsWindowController.shared.show()
            return
        }
        let menu = buildMenu()
        menu.appearance = NSApp.appearance
        menu.popUp(positioning: nil, at: NSPoint(x: -10, y: button.bounds.height + 10), in: button)
    }

    private func buildMenu() -> NSMenu {
        let session = SessionManager.shared
        let credentials = CredentialsManager.shared
        let preflight = PreflightState.shared
        let canRun = preflight.canRunAutomation
        let notReadyKey = preflight.notReadyReasonKey
        let isOffline = (notReadyKey == "preflight.network_offline")
        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: L10n.string("menu.about"), action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())

        // When done for the day, don’t show an actionable Clock In (can’t clock in again until tomorrow).
        if !canRun, let reasonKey = notReadyKey {
            let reason = L10n.string(reasonKey)
            let notReadyItem = NSMenuItem(title: "\(L10n.string("status.not_ready")) — \(reason)", action: nil, keyEquivalent: "")
            notReadyItem.isEnabled = false
            menu.addItem(notReadyItem)
        }

        // Today summary: show human-readable label for today's status/span.
        let todayBase = Self.todaySummaryBase(session: session)
        let todayTitle = String(format: L10n.string("menu.today_label"), todayBase)
        let todayItem = NSMenuItem(title: todayTitle, action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        menu.addItem(todayItem)
        menu.addItem(NSMenuItem.separator())

        if !session.isDoneForTheDay {
            let clockTitle = session.isWorking ? L10n.string("menu.clock_out") : L10n.string("menu.clock_in")
            let clockEnabled = canRun && credentials.hasStoredCredentials && (session.isWorking || !session.isDoneForTheDay)
            let clockItem = NSMenuItem(title: clockTitle, action: session.isWorking ? #selector(clockOut) : #selector(clockIn), keyEquivalent: "")
            clockItem.target = self
            clockItem.isEnabled = clockEnabled
            menu.addItem(clockItem)
        }

        let syncItem = NSMenuItem(title: L10n.string("menu.sync"), action: #selector(sync), keyEquivalent: "")
        syncItem.target = self
        syncItem.isEnabled = canRun && credentials.hasStoredCredentials
        menu.addItem(syncItem)
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: L10n.string("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = !isOffline
        menu.addItem(settingsItem)

        if AppEnvironment.isLocal {
            menu.addItem(NSMenuItem.separator())
            let developMenu = NSMenu()
            for kind in SessionManager.TestAlertKind.allCases {
                let item = NSMenuItem(title: "Test: \(kind.rawValue)", action: #selector(showTestAlert(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = kind.rawValue
                developMenu.addItem(item)
            }
            let developSub = NSMenuItem(title: "Develop", action: nil, keyEquivalent: "")
            developSub.submenu = developMenu
            menu.addItem(developSub)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.string("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openAbout() {
        AppLogger.info("User: menu About")
        let session = SessionManager.shared
        let credentials = CredentialsManager.shared
        let settings = AppSettings.shared
        let baseURL = settings.effectiveKotBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let host: String
        if !baseURL.isEmpty, let url = URL(string: baseURL), let h = url.host, !h.isEmpty {
            host = url.port.map { "\(h):\($0)" } ?? h
        } else {
            host = "—"
        }
        AboutWindowController.shared.show(
            status: session.aboutStatusText,
            host: host.isEmpty ? "—" : host,
            username: credentials.hasStoredCredentials ? credentials.username : nil,
            nodeVersion: AutomationInvoker.shared.nodeVersionForAbout
        )
    }

    @objc private func clockIn() {
        AppLogger.info("User: menu Clock In")
        SessionManager.shared.clockInFromMenu()
    }

    @objc private func clockOut() {
        AppLogger.info("User: menu Clock Out")
        SessionManager.shared.stopWorkFlow()
    }

    @objc private func sync() {
        AppLogger.info("User: menu Sync timecard")
        SessionManager.shared.recheckTimecardStatus()
    }

    @objc private func openSettings() {
        AppLogger.info("User: menu Settings")
        SettingsWindowController.shared.show()
    }

    @objc private func showTestAlert(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = SessionManager.TestAlertKind(rawValue: raw) else { return }
        SessionManager.shared.showTestAlert(kind)
    }

    @objc private func quit() {
        AppLogger.info("User: menu Quit")
        NSApplication.shared.terminate(nil)
    }
}
