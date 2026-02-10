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

/// Snapshot of environment/settings passed into each preflight task.
struct PreflightContext {
    let environment: String
    let effectiveURL: String
    let hasCredentials: Bool
    let networkConnected: Bool
    let keychainError: String?
}

/// One preflight check (e.g. node, network, keychain, site reachability).
protocol PreflightTask {
    func execute(context: PreflightContext) -> PreflightResult
}

