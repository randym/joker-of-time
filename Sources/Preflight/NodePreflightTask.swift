import Foundation

/// Node.js path/version check.
struct NodePreflightTask: PreflightTask {
    static let failureReasonKey = "preflight.node_not_found"
    static let failureIconName = "circle.slash"

    func execute() -> PreflightResult {
        let ok = AutomationInvoker.shared.performStartupNodeCheck()
        PreflightState.shared.setNodeResolved(ok)
        if ok {
            AppLogger.verbose("Preflight: node OK (\(AutomationInvoker.shared.nodeVersionForAbout))")
            return .success
        } else {
            AppLogger.verbose("Preflight: node failed — automation unavailable")
            return .failure(PreflightFailure(reasonKey: Self.failureReasonKey, iconName: Self.failureIconName, kind: .nodeNotResolved))
        }
    }
}
