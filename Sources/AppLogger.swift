import Foundation
import os

/// Logging: unified log (Console.app) always; file only in dev so production users don't fill disk.
enum AppLogger {
    private static let subsystem = "io.github.randym.JokerOfTime"
    private static let log = Logger(subsystem: subsystem, category: "app")

    private static var logFileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("JokerOfTime", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clocker.log")
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func info(_ message: String) {
        log.info("\(message, privacy: .public)")
        if AppEnvironment.isLocal { appendToFile(level: "INFO", message: message) }
    }

    static func error(_ message: String) {
        log.error("\(message, privacy: .public)")
        if AppEnvironment.isLocal { appendToFile(level: "ERROR", message: message) }
    }

    static func debug(_ message: String) {
        log.debug("\(message, privacy: .public)")
        if AppEnvironment.isLocal { appendToFile(level: "DEBUG", message: message) }
    }

    private static func appendToFile(level: String, message: String) {
        guard let url = logFileURL else { return }
        let line = "\(dateFormatter.string(from: Date())) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
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
