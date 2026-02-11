import Foundation

/// Log level for AppLogger. When level is N, messages at N and "lower" verbosity are emitted (e.g. at info we emit error, debug, info).
enum LogLevel: String, CaseIterable, Comparable, Identifiable {
    case none
    case debug
    case info
    case verbose

    var id: String { rawValue }

    var ordinal: Int {
        switch self {
        case .none: return 0
        case .debug: return 1
        case .info: return 2
        case .verbose: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}

/// User-configurable settings for JokerOfTime.
/// Production (dist .app) and dev (swift run) never share storage: each uses a separate UserDefaults key so settings and user data cannot leak between builds.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Default King of Time endpoint when user has not set a custom URL.
    static let defaultKotURL = "https://s3.ta.kingoftime.jp/independent/recorder2/personal/"

    @Published var kotBaseURL: String
    @Published var workdayHours: Double
    @Published var runOnLogin: Bool
    /// Minimum log level to emit. Default: none in production, verbose in local.
    @Published var logLevel: LogLevel
    /// User-set path to Node.js binary; when non-empty we use this instead of auto-resolving. Empty = use resolved path (Homebrew / which node).
    @Published var nodePath: String

    private static let defaultsKeyProduction = "JokerOfTimeSettings"
    private static let defaultsKeyDev = "JokerOfTimeSettings.Dev"
    private static var defaultsKey: String { AppEnvironment.isLocal ? defaultsKeyDev : defaultsKeyProduction }

    private init() {
        let defaults = UserDefaults.standard
        let key = Self.defaultsKey
        let defaultLogLevel: LogLevel = AppEnvironment.isLocal ? .verbose : .none
        if let stored = defaults.dictionary(forKey: key) {
            kotBaseURL = stored["kotBaseURL"] as? String ?? ""
            workdayHours = stored["workdayHours"] as? Double ?? 9
            runOnLogin = stored["runOnLogin"] as? Bool ?? true
            nodePath = stored["nodePath"] as? String ?? ""
            if let raw = stored["logLevel"] as? String, let level = LogLevel(rawValue: raw) {
                logLevel = level
            } else if let enabled = stored["loggingEnabled"] as? Bool {
                logLevel = enabled ? .info : .none
            } else {
                logLevel = defaultLogLevel
            }
        } else {
            kotBaseURL = ""
            workdayHours = 9
            runOnLogin = true
            nodePath = ""
            logLevel = defaultLogLevel
        }
    }

    func save() {
        let payload: [String: Any] = [
            "kotBaseURL": kotBaseURL,
            "workdayHours": workdayHours,
            "runOnLogin": runOnLogin,
            "nodePath": nodePath,
            "logLevel": logLevel.rawValue
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

    /// Regex: http or https, then host (localhost | IPv4 | hostname), optional port, optional path. Rejects typos like ht//, htp://.
    private static let kotURLRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^(https?):\/\/(localhost|\d{1,3}(?:\.\d{1,3}){3}|[A-Za-z0-9\-._~%]+)(?::\d{1,5})?(\/[^\s]*)?$"#,
        options: []
    )

    /// Validation error message for the KOT URL field, or nil if valid. Shared so SettingsView and SettingsWindowController can block close consistently.
    static func kotURLValidationError(trimmed: String) -> String? {
        if trimmed.isEmpty { return nil }
        let lower = trimmed.lowercased()
        if lower.contains("//") && !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            return L10n.string("settings.url_invalid")
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let regex = kotURLRegex else {
            return L10n.string("settings.url_invalid")
        }
        let nsRange = NSRange(withScheme.startIndex..<withScheme.endIndex, in: withScheme)
        guard regex.firstMatch(in: withScheme, options: [], range: nsRange) != nil else {
            return L10n.string("settings.url_invalid")
        }
        let lowerWithScheme = withScheme.lowercased()
        if !AppEnvironment.isLocal && lowerWithScheme.hasPrefix("http://") {
            return L10n.string("settings.url_use_https")
        }
        return nil
    }
}

