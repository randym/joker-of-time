import Foundation

/// User-configurable settings for JokerOfTime.
/// Production (dist .app) and dev (swift run) never share storage: each uses a separate UserDefaults key so settings and user data cannot leak between builds.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Default King of Time endpoint when user has not set a custom URL.
    static let defaultKotURL = "https://s3.ta.kingoftime.jp/independent/recorder2/personal/"

    @Published var kotBaseURL: String
    @Published var workdayHours: Double
    @Published var runOnLogin: Bool

    private static let defaultsKeyProduction = "JokerOfTimeSettings"
    private static let defaultsKeyDev = "JokerOfTimeSettings.Dev"
    private static var defaultsKey: String { AppEnvironment.isLocal ? defaultsKeyDev : defaultsKeyProduction }

    private init() {
        let defaults = UserDefaults.standard
        let key = Self.defaultsKey
        if let stored = defaults.dictionary(forKey: key) {
            kotBaseURL = stored["kotBaseURL"] as? String ?? ""
            workdayHours = stored["workdayHours"] as? Double ?? 9
            runOnLogin = stored["runOnLogin"] as? Bool ?? true
        } else {
            kotBaseURL = ""
            workdayHours = 9
            runOnLogin = true
        }
    }

    func save() {
        let payload: [String: Any] = [
            "kotBaseURL": kotBaseURL,
            "workdayHours": workdayHours,
            "runOnLogin": runOnLogin
        ]
        UserDefaults.standard.set(payload, forKey: Self.defaultsKey)
    }

    /// URL used for King of Time: saved setting if set, else KOT_BASE_URL env (e.g. from .env.local), else default.
    var effectiveKotBaseURL: String {
        let saved = kotBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty { return saved }
        let env = ProcessInfo.processInfo.environment["KOT_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !env.isEmpty { return env }
        return Self.defaultKotURL
    }

    /// Convenience for time-based calculations.
    var workDuration: TimeInterval {
        max(0, workdayHours) * 60 * 60
    }
}

