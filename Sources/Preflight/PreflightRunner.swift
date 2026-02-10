import Foundation

/// Central preflight: run reusable checks, update PreflightState, shared failure handling. Call before time card flow.
enum PreflightRunner {

    /// Ordered list of preflight tasks. Run in sequence; first failure wins.
    private static let tasks: [PreflightTask] = [
        NodePreflightTask(),
        NetworkPreflightTask(),
        KeychainPreflightTask(),
        SiteReachabilityPreflightTask()
    ]

    /// Run all preflight checks and return a rich outcome.
    static func runPreflightOutcome() -> PreflightOutcome {
        // Sync keychain error from CredentialsManager so tasks see fresh state.
        PreflightState.shared.syncKeychainErrorFromCredentialsManager()

        let env = AppEnvironment.current
        let settings = AppSettings.shared
        let effectiveURL = settings.effectiveKotBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCreds = CredentialsManager.shared.hasStoredCredentials
        let networkConnected = NetworkMonitor.shared.isConnected
        let keychainError = CredentialsManager.shared.keychainErrorMessage

        let context = PreflightContext(
            environment: env,
            effectiveURL: effectiveURL,
            hasCredentials: hasCreds,
            networkConnected: networkConnected,
            keychainError: keychainError
        )

        var failure: PreflightFailure?
        for task in tasks {
            switch task.execute(context: context) {
            case .success:
                continue
            case .failure(let f):
                failure = f
                break
            }
        }

        if let f = failure {
            PreflightState.shared.setLastFailure(f)
            AppLogger.verbose("Preflight: not ready — \(f.reasonKey)")
            return PreflightOutcome(success: false, failure: f)
        } else {
            PreflightState.shared.setLastFailure(nil)
            AppLogger.verbose("Preflight: all checks passed — ready to run automation")
            return PreflightOutcome(success: true, failure: nil)
        }
    }

    /// Backwards-compatible convenience: true when preflight passed.
    static func runPreflight() -> Bool {
        runPreflightOutcome().success
    }
}

