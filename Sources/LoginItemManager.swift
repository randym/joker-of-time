import Foundation
import ServiceManagement

/// Manages "run at login" behavior. When the built app includes the LoginItemHelper (in Contents/Library/LoginItems),
/// we register that helper so it can launch the main app with --launched-at-login. Otherwise we use mainApp.
final class LoginItemManager {
    static let shared = LoginItemManager()

    private static let loginItemHelperBundleID = "io.github.randym.JokerOfTime.LoginItemHelper"

    private init() {}

    /// True when the app bundle contains LoginItemHelper.app (production build from build-app.sh).
    private var hasLoginItemHelper: Bool {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/LoginItemHelper.app", isDirectory: true)
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            AppLogger.error("LoginItem: run-on-login requires macOS 13 or later")
            return
        }
        let service: SMAppService
        if hasLoginItemHelper {
            service = SMAppService.loginItem(identifier: Self.loginItemHelperBundleID)
        } else {
            service = SMAppService.mainApp
        }
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
    }
}

