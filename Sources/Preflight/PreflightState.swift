import Foundation
import Combine

/// Readiness state for preflight checks. Updated when checks run or network changes. Read by StatusItemManager and menu for icon and enable/disable.
final class PreflightState: ObservableObject {
    static let shared = PreflightState()

    /// Node.js resolved at last check. nil = not yet run.
    @Published private(set) var nodeResolved: Bool?

    /// Network connected; kept in sync with NetworkMonitor.
    @Published private(set) var networkConnected: Bool = true

    /// Can login (first timecard or credentials-save probe). nil = not yet run.
    @Published private(set) var canLoginPassed: Bool?

    /// Keychain error message in production when load fails; nil when OK or not checked.
    @Published private(set) var keychainError: String?

    /// Site reachable; set false when timecard fetch fails (e.g. bad URL, cannot reach server).
    @Published private(set) var siteReachable: Bool = true

    /// Failure from the last preflight run, if any. Holds concrete reasonKey and iconName from the task that failed.
    @Published private(set) var lastFailure: PreflightFailure?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        networkConnected = NetworkMonitor.shared.isConnected
        observeNetwork()
    }

    private func observeNetwork() {
        NotificationCenter.default.publisher(for: NetworkMonitor.connectivityDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                if let connected = note.userInfo?["isConnected"] as? Bool {
                    self.networkConnected = connected
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Updates (called by preflight and Settings)

    func setNodeResolved(_ resolved: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.nodeResolved = resolved
        }
    }

    func setNetworkConnected(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.networkConnected = connected
        }
    }

    func setCanLoginPassed(_ passed: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.canLoginPassed = passed
        }
    }

    func setKeychainError(_ message: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.keychainError = message
        }
    }

    func setSiteReachable(_ reachable: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.siteReachable = reachable
        }
    }

    func setLastFailure(_ failure: PreflightFailure?) {
        DispatchQueue.main.async { [weak self] in
            self?.lastFailure = failure
        }
    }

    /// Call after running credentials load in production to sync keychain error from CredentialsManager.
    func syncKeychainErrorFromCredentialsManager() {
        let message = CredentialsManager.shared.keychainErrorMessage
        setKeychainError(message)
    }

    /// True if automation can run: Node resolved, network connected, credentials stored, no credentials/keychain error, site reachable.
    /// Can-login is not required for "can run" (we discover it on first timecard).
    var canRunAutomation: Bool {
        guard nodeResolved == true else { return false }
        guard networkConnected else { return false }
        // Missing credentials is treated as a keychain/credentials error for readiness.
        guard CredentialsManager.shared.hasStoredCredentials else { return false }
        guard keychainError == nil else { return false }
        guard siteReachable else { return false }
        return true
    }

    /// When !canRunAutomation, L10n key for the primary reason. From lastFailure when set, else fallback key.
    var notReadyReasonKey: String? {
        guard !canRunAutomation else { return nil }
        if let f = lastFailure { return f.reasonKey }
        if !networkConnected { return "preflight.network_offline" }
        // Credentials missing OR an explicit keychain error → treat as one "credentials" error bucket.
        if !CredentialsManager.shared.hasStoredCredentials { return "preflight.keychain_error" }
        if let err = keychainError, !err.isEmpty { return "preflight.keychain_error" }
        if nodeResolved != true { return "preflight.node_not_found" }
        if !siteReachable { return "preflight.cannot_reach_site" }
        return "preflight.not_ready"
    }

    /// When !canRunAutomation, SF Symbol name for status icon. From lastFailure when set, else fallback icon.
    var notReadyIconName: String? {
        guard !canRunAutomation else { return nil }
        if let f = lastFailure { return f.iconName }
        if !networkConnected { return "wifi.exclamationmark.circle" }
        // Credentials missing OR keychain error → credentials icon.
        if !CredentialsManager.shared.hasStoredCredentials { return "person.crop.circle.badge.exclamationmark" }
        if let err = keychainError, !err.isEmpty { return "person.crop.circle.badge.exclamationmark" }
        if nodeResolved != true { return "circle.slash" }
        if !siteReachable { return "mappin.slash.circle" }
        return "circle.slash"
    }
}
