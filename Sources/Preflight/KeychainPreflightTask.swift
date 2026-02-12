import Foundation

/// Keychain / credentials load check.
struct KeychainPreflightTask: PreflightTask {
    static let failureReasonKey = "preflight.keychain_error"
    static let failureIconName = "person.crop.circle.badge.exclamationmark"

    func execute() -> PreflightResult {
        let hasCreds = CredentialsManager.shared.hasStoredCredentials
        let err = CredentialsManager.shared.keychainErrorMessage

        // Keep PreflightState in sync with the latest keychain/credentials error.
        PreflightState.shared.setKeychainError(err)

        // OK only when we both have stored credentials AND no keychain error message.
        let ok = hasCreds && (err == nil || err?.isEmpty == true)
        if ok {
            AppLogger.verbose("Preflight: credentials OK")
            return .success
        }

        if !hasCreds && (err == nil || err?.isEmpty == true) {
            AppLogger.verbose("Preflight: no credentials stored")
        } else {
            AppLogger.verbose("Preflight: keychain/credentials failed — \(err ?? "unknown")")
        }

        return .failure(
            PreflightFailure(
                reasonKey: Self.failureReasonKey,
                iconName: Self.failureIconName,
                kind: .keychainError
            )
        )
    }
}
