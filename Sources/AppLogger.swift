import Foundation

/// Logging to stderr and ~/Library/Application Support/JokerOfTime/[env].log. Gated by AppSettings.logLevel.
enum AppLogger {
    /// ~/Library/Application Support/JokerOfTime/[env].log. Nil when log level is .none.
    private static var logFileURL: URL? {
        guard AppSettings.shared.logLevel != .none else { return nil }
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("JokerOfTime", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let env = AppEnvironment.current
        return dir.appendingPathComponent("\(env).log")
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func log(_ message: String, level: LogLevel, tag: String) {
        let minLevel = AppSettings.shared.logLevel
        guard minLevel != .none, minLevel >= level else { return }
        fputs("[\(tag)] \(message)\n", stderr)
        appendToFile("\(dateFormatter.string(from: Date())) [\(tag)] \(message)")
    }

    static func error(_ message: String) {
        log(message, level: .debug, tag: "ERROR")
    }

    static func debug(_ message: String) {
        log(message, level: .debug, tag: "DEBUG")
    }

    static func info(_ message: String) {
        log(message, level: .info, tag: "INFO")
    }

    static func verbose(_ message: String) {
        log(message, level: .verbose, tag: "VERBOSE")
    }

    private static func appendToFile(_ line: String) {
        guard let url = logFileURL else { return }
        let withNewline = line.hasSuffix("\n") ? line : line + "\n"
        guard let data = withNewline.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url)
        }
    }
}
