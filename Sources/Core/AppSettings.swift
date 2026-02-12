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
/// Production and dev settings are stored separately to prevent dev-only settings from leaking into production builds.
/// - Production settings: workdayHours, runOnLogin (available in all builds)
/// - Dev settings: kotBaseURL, nodePath, logLevel (dev builds only)
/// Production builds only read/write production settings. Dev builds read/write both.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Default King of Time endpoint when user has not set a custom URL.
    static let defaultKotURL = "https://s3.ta.kingoftime.jp/independent/recorder2/personal/"

    @Published var workdayHours: Double
    @Published var runOnLogin: Bool
    @Published var kotBaseURL: String
    /// Minimum log level to emit. Default: none in production, verbose in local.
    @Published var logLevel: LogLevel
    /// User-set path to Node.js binary; when non-empty we use this instead of auto-resolving. Empty = use resolved path (Homebrew / which node).
    @Published var nodePath: String

    private static let defaultsKeyProduction = "JokerOfTimeSettings"
    private static let defaultsKeyDev = "JokerOfTimeSettings.Dev"
    
    private static let defaultWorkdayHours: Double = 9
    private static let defaultRunOnLogin: Bool = true
    private static let defaultNodePath: String = ""
    private static let defaultLogLevelDev: LogLevel = .verbose
    private static let defaultLogLevelProd: LogLevel = .none

    private init() {
        let defaults = UserDefaults.standard
        
        let prodStored = defaults.dictionary(forKey: Self.defaultsKeyProduction)

        workdayHours = prodStored?["workdayHours"] as? Double ?? Self.defaultWorkdayHours
        runOnLogin = prodStored?["runOnLogin"] as? Bool ?? Self.defaultRunOnLogin
        
        kotBaseURL = Self.defaultKotURL
        nodePath = Self.defaultNodePath
        logLevel = Self.defaultLogLevelProd
        
        guard AppEnvironment.isLocal else { return }
        
        let devStored = defaults.dictionary(forKey: Self.defaultsKeyDev)

        kotBaseURL = devStored?["kotBaseURL"] as? String ?? kotBaseURL
        nodePath = devStored?["nodePath"] as? String ?? nodePath
        logLevel = (devStored?["logLevel"] as? String).flatMap(LogLevel.init) ?? logLevel
    }

    func save() {
        let defaults = UserDefaults.standard
        
        let prodPayload: [String: Any] = [
            "workdayHours": workdayHours,
            "runOnLogin": runOnLogin
        ]
        defaults.set(prodPayload, forKey: Self.defaultsKeyProduction)
        
        guard AppEnvironment.isLocal else { return }
        
        let devPayload: [String: Any] = [
            "kotBaseURL": kotBaseURL,
            "nodePath": nodePath,
            "logLevel": logLevel.rawValue
        ]
        defaults.set(devPayload, forKey: Self.defaultsKeyDev)
    }


    /// Convenience for time-based calculations.
    var workDuration: TimeInterval {
        max(0, workdayHours) * 60 * 60
    }
}

