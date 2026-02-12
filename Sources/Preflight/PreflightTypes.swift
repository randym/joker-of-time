import Foundation

/// Kind of preflight failure; used only for alert/Settings behavior (e.g. open Settings vs not).
enum PreflightFailureKind {
    case nodeNotResolved
    case networkOffline
    case keychainError
    case cannotReachSite
    case unknown
}

/// Concrete failure from a preflight task: key and icon come from the task, not from a central switch.
struct PreflightFailure {
    let reasonKey: String
    let iconName: String
    let kind: PreflightFailureKind
}

/// Result of running a single preflight task.
enum PreflightResult {
    case success
    case failure(PreflightFailure)
}

/// Outcome of the full preflight run.
struct PreflightOutcome {
    let success: Bool
    let failure: PreflightFailure?
}

/// One preflight check (e.g. node, network, keychain, site reachability).
protocol PreflightTask {
    func execute() -> PreflightResult
}

/// Where preflight was triggered from, so UI can behave slightly differently if needed.
enum PreflightUIContext {
    case startup
    case manualSync
    case autoResync
    case settingsClose
}