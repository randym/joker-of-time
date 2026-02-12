import Foundation

/// Site reachability (base URL / host issues) — only when network is up.
struct SiteReachabilityPreflightTask: PreflightTask {
    static let failureReasonKey = "preflight.cannot_reach_site"
    static let failureIconName = "mappin.slash.circle"
    
    var isTransient: Bool { true }  // Site can come back up

    func execute() -> PreflightResult {
        guard NetworkMonitor.shared.isConnected, CredentialsManager.shared.hasStoredCredentials else {
            PreflightState.shared.setSiteReachable(true)
            return .success
        }

        let reachable = AutomationInvoker.shared.quickSiteReachabilityCheck(networkConnected: NetworkMonitor.shared.isConnected)
        PreflightState.shared.setSiteReachable(reachable)
        if reachable {
            AppLogger.verbose("Preflight: site reachable")
            return .success
        } else {
            AppLogger.verbose("Preflight: site not reachable")
            return .failure(PreflightFailure(reasonKey: Self.failureReasonKey, iconName: Self.failureIconName, kind: .cannotReachSite, isTransient: isTransient))
        }
    }
}
