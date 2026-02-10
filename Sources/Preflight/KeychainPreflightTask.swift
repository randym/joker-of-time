import Foundation

/// Keychain / credentials load check.
struct KeychainPreflightTask: PreflightTask {
    static let failureReasonKey = "preflight.keychain_error"
    static let failureIconName = "person.crop.circle.badge.exclamationmark"

    func execute(context: PreflightContext) -> PreflightResult {
        let err = context.keychainError
        let ok = err == nil || err?.isEmpty == true
        PreflightState.shared.setKeychainError(err)
        if ok {
            AppLogger.verbose("Preflight: keychain OK")
            return .success
        } else {
            AppLogger.verbose("Preflight: keychain failed — \(err ?? "unknown")")
            return .failure(PreflightFailure(reasonKey: Self.failureReasonKey, iconName: Self.failureIconName, kind: .keychainError))
        }
    }
}
