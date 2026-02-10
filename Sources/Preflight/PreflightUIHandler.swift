import AppKit

/// Where preflight was triggered from, so UI can behave slightly differently if needed.
enum PreflightUIContext {
    case startup
    case startupFromBoot
    case manualSync
    case autoResync
    case settingsClose
}

/// Maps preflight failure (kind) + context to alerts and (optionally) opening Settings.
enum PreflightUIHandler {
    static func handleFailure(_ failure: PreflightFailure, context: PreflightUIContext) {
        AppLogger.info("Preflight: UI kind=\(failure.kind) context=\(context)")
        if context == .startupFromBoot {
            AppLogger.info("Preflight: suppressing alerts (startupFromBoot) kind=\(failure.kind) — no dialog shown")
            return
        }

        switch failure.kind {
        case .networkOffline:
            if context == .autoResync { return }
            AppLogger.info("Preflight: showing network offline alert")
            SessionManager.shared.showNetworkOfflineAlert()

        case .cannotReachSite:
            AppLogger.info("Preflight: showing cannot reach site alert")
            SessionManager.shared.showCannotReachSiteAlert()

        case .nodeNotResolved:
            AppLogger.info("Preflight: showing node not found alert")
            SessionManager.shared.showNodeNotFoundAlert()

        case .keychainError, .unknown:
            AppLogger.info("Preflight: failure kind=\(failure.kind) (no alert)")
            break
        }
    }
}

