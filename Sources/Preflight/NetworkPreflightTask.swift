import Foundation

/// Network connectivity check (online/offline).
struct NetworkPreflightTask: PreflightTask {
    static let failureReasonKey = "preflight.network_offline"
    static let failureIconName = "wifi.exclamationmark.circle"

    func execute(context: PreflightContext) -> PreflightResult {
        let connected = context.networkConnected
        PreflightState.shared.setNetworkConnected(connected)
        if connected {
            AppLogger.verbose("Preflight: network OK")
            return .success
        } else {
            AppLogger.verbose("Preflight: network offline")
            return .failure(PreflightFailure(reasonKey: Self.failureReasonKey, iconName: Self.failureIconName, kind: .networkOffline))
        }
    }
}
