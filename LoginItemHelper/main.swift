import Foundation

/// Login item helper: when launched at login by macOS, launches the main app executable with --launched-at-login and exits.
/// We live in MainApp.app/Contents/Library/LoginItems/LoginItemHelper.app.
@main
struct LoginItemHelper {
    static func main() {
        let mainAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent()   // LoginItems
            .deletingLastPathComponent()   // Library
            .deletingLastPathComponent()   // Contents
            .deletingLastPathComponent()   // JokerOfTime.app

        let executableURL = mainAppURL
            .appendingPathComponent("Contents/MacOS/JokerOfTime", isDirectory: false)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--launched-at-login"]

        do {
            try process.run()
            exit(0)
        } catch {
            fputs("LoginItemHelper: failed to launch main app: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
