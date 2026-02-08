import Foundation
import ServiceManagement

/// Manages \"run at login\" behavior for JokerOfTime.
final class LoginItemManager {
    static let shared = LoginItemManager()

    private init() {}

    func setEnabled(_ enabled: Bool) {
        // For a single-app bundle, use SMAppService.mainApp on macOS 13+.
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
                AppLogger.info("LoginItem: setEnabled=\(enabled) succeeded")
            } catch {
                AppLogger.error("LoginItem: failed to setEnabled=\(enabled): \(error.localizedDescription)")
            }
        } else {
            AppLogger.error("LoginItem: run-on-login requires macOS 13 or later")
        }
    }
}

