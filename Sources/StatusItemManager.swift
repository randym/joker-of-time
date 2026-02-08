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
    private var lastIconState: (running: Bool, working: Bool) = (false, false)

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

    /// Read SessionManager and set status item image. Call on main.
    private func updateIcon(force: Bool) {
        let session = SessionManager.shared
        let running = session.isAutomationRunning
        let working = session.isWorking
        let state = (running: running, working: working)
        if !force && state.0 == lastIconState.0 && state.1 == lastIconState.1 { return }
        lastIconState = state

        if running {
            startSpinnerTimer()
            tickSpinner()
            return
        }
        stopSpinnerTimer()
        guard let button = statusItem?.button else { return }
        let symbolName = working ? "clock.fill" : "clock"
        let desc = working ? L10n.string("status.working") : L10n.string("status.idle")
        button.image = Self.templateImage(systemSymbolName: symbolName, size: Self.iconSize, accessibilityDescription: desc)
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
        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: L10n.string("menu.about"), action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())

        // When done for the day, don’t show an actionable Clock In (can’t clock in again until tomorrow).
        if !session.isDoneForTheDay {
            let clockTitle = session.isWorking ? L10n.string("menu.clock_out") : L10n.string("menu.clock_in")
            let clockEnabled = credentials.hasStoredCredentials && (session.isWorking || !session.isDoneForTheDay)
            let clockItem = NSMenuItem(title: clockTitle, action: session.isWorking ? #selector(clockOut) : #selector(clockIn), keyEquivalent: "")
            clockItem.target = self
            clockItem.isEnabled = clockEnabled
            menu.addItem(clockItem)
        }

        if session.isDoneForTheDay {
            let outTime = session.clockedOutTime.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—"
            let statusItem = NSMenuItem(title: L10n.string("menu.clocked_out_at", outTime), action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }

        let syncItem = NSMenuItem(title: L10n.string("menu.sync"), action: #selector(sync), keyEquivalent: "")
        syncItem.target = self
        syncItem.isEnabled = credentials.hasStoredCredentials
        menu.addItem(syncItem)
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: L10n.string("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.string("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openAbout() {
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
        SessionManager.shared.clockInFromMenu()
    }

    @objc private func clockOut() {
        SessionManager.shared.stopWorkFlow()
    }

    @objc private func sync() {
        SessionManager.shared.recheckTimecardStatus()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
