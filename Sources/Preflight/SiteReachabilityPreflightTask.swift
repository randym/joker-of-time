import Foundation

/// Site reachability (base URL / host issues) — only when network is up.
struct SiteReachabilityPreflightTask: PreflightTask {
    static let failureReasonKey = "preflight.cannot_reach_site"
    static let failureIconName = "link.circle"

    func execute(context: PreflightContext) -> PreflightResult {
        guard context.networkConnected, context.hasCredentials else {
            PreflightState.shared.setSiteReachable(true)
            return .success
        }

        let reachable = AutomationInvoker.shared.quickSiteReachabilityCheck(networkConnected: context.networkConnected)
        PreflightState.shared.setSiteReachable(reachable)
        if reachable {
            AppLogger.verbose("Preflight: site reachable")
            return .success
        } else {
            AppLogger.verbose("Preflight: site not reachable")
            return .failure(PreflightFailure(reasonKey: Self.failureReasonKey, iconName: Self.failureIconName, kind: .cannotReachSite))
        }
    }
}
