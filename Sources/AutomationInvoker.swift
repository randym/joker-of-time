import Foundation

/// JSON payload from automation `timecard-status` command.
struct TimecardStatusPayload: Codable {
    let shouldWorkToday: Bool
    let clockedIn: Bool
    let clockInTime: String?
    let clockedOut: Bool
    let clockOutTime: String?
    let todayLabel: String?
}

/// Runs the bundled Node automation (clock-in / clock-out / timecard-status) with credentials from Keychain.
final class AutomationInvoker {
    static let shared = AutomationInvoker()

    enum ClockAction {
        case clockIn
        case clockOut
    }

    /// Guard failure reasons from automation (stderr message contains these).
    static let alreadyClockedInMessage = "ALREADY_CLOCKED_IN"
    static let alreadyClockedOutMessage = "ALREADY_CLOCKED_OUT"
    static let notClockedInMessage = "NOT_CLOCKED_IN"
    static let loginFailedMessage = "LOGIN_FAILED"
    static let networkErrorMessage = "NETWORK_ERROR"

    /// Full path to node binary, resolved once at startup via login shell so asdf/nvm work. We run this path directly so the clock command doesn't depend on PATH.
    private var resolvedNodePath: String?
    /// Node version string from startup check (e.g. "v22.11.0"); nil if not resolved or not found.
    private var resolvedNodeVersion: String?

    /// For About dialog: "v22.11.0" or "not found" if node was not resolved at startup.
    var nodeVersionForAbout: String {
        resolvedNodeVersion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? resolvedNodeVersion!
            : "not found"
    }

    /// Daemon: one long-lived browser process; we send JSON commands on stdin and read one JSON line per response from stdout. Serialized so only one command in flight.
    private let daemonQueue = DispatchQueue(label: "AutomationInvoker.daemon")
    private var daemonProcess: Process?
    private var daemonStdinHandle: FileHandle?
    private var daemonStdoutHandle: FileHandle?
    private var daemonStderrHandle: FileHandle?

    private init() {}

    /// Start the Node daemon (one browser) if not already running. Call on daemonQueue. Returns true if daemon is ready.
    private func ensureDaemonRunning(automationDir: URL, cliURL: URL, nodePath: String) -> Bool {
        if let proc = daemonProcess, proc.isRunning {
            return true
        }
        daemonProcess?.terminate()
        daemonStdinHandle?.closeFile()
        daemonStdoutHandle?.closeFile()
        daemonStderrHandle?.closeFile()
        daemonProcess = nil
        daemonStdinHandle = nil
        daemonStdoutHandle = nil
        daemonStderrHandle = nil
        var env = ProcessInfo.processInfo.environment
        env["KOT_BASE_URL"] = AppSettings.shared.effectiveKotBaseURL
        if AppEnvironment.isLocal {
            env["JOT_DEV"] = "1"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [cliURL.path, "daemon"]
        process.currentDirectoryURL = automationDir
        process.environment = env
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            daemonProcess = process
            daemonStdinHandle = stdinPipe.fileHandleForWriting
            daemonStdoutHandle = stdoutPipe.fileHandleForReading
            daemonStderrHandle = stderrPipe.fileHandleForReading
            forwardDaemonStderrToLog(process: process, stderr: stderrPipe.fileHandleForReading)
            AppLogger.info("Automation: daemon started (one browser, reuse for all commands)")
            return true
        } catch {
            AppLogger.error("Automation: failed to start daemon: \(error.localizedDescription)")
            return false
        }
    }

    /// Read daemon stderr on a background queue and log each line with Automation: prefix.
    private func forwardDaemonStderrToLog(process: Process, stderr: FileHandle) {
        DispatchQueue.global(qos: .utility).async {
            var buffer = ""
            while true {
                let data = stderr.availableData
                if data.isEmpty {
                    if !process.isRunning { break }
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                }
                if let chunk = String(data: data, encoding: .utf8) {
                    buffer += chunk
                    if buffer.contains("\n") {
                        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
                        let complete = lines.dropLast()
                        buffer = lines.last.map(String.init) ?? ""
                        for line in complete {
                            AppLogger.verbose("Automation: \(line)")
                        }
                    }
                }
            }
            if !buffer.trimmingCharacters(in: .whitespaces).isEmpty {
                AppLogger.verbose("Automation: \(buffer)")
            }
        }
    }

    /// Send one JSON command to the daemon and read one line of response. Call on daemonQueue. Returns the response line or nil on failure.
    private func sendDaemonCommandAndReadLine(command: [String: Any]) -> String? {
        guard let stdin = daemonStdinHandle, let stdout = daemonStdoutHandle,
              let proc = daemonProcess, proc.isRunning else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              let line = String(data: data, encoding: .utf8) else { return nil }
        let lineWithNewline = line + "\n"
        guard let writeData = lineWithNewline.data(using: .utf8) else { return nil }
        stdin.write(writeData)
        try? stdin.synchronize()
        var buffer = Data()
        while true {
            let chunk = stdout.availableData
            if chunk.isEmpty {
                if !proc.isRunning { return nil }
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            buffer.append(chunk)
            if let str = String(data: buffer, encoding: .utf8), str.contains("\n") {
                let firstLine = str.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)[0]
                return String(firstLine).trimmingCharacters(in: .whitespaces)
            }
        }
    }

    /// Run the clock automation. Completion is called on a background thread. On failure, `output` contains stderr for guard detection (ALREADY_CLOCKED_IN etc.).
    func runClock(action: ClockAction, completion: @escaping (Bool, _ output: String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let (success, output) = self.runClockSync(action: action)
            completion(success, output)
        }
    }

    private func runClockSync(action: ClockAction) -> (Bool, String) {
        guard let automationDir = resolveAutomationDirectory(),
              let cliURL = cliURL(automationDir: automationDir) else {
            AppLogger.error("Automation: could not find automation directory or cli.js")
            return (false, "")
        }
        guard let creds = CredentialsManager.shared.loadCredentials() else {
            AppLogger.error("Automation: no stored credentials available")
            return (false, "")
        }
        guard let nodePath = resolvedNodePath else {
            AppLogger.error("Automation: node path not resolved (run startup check first)")
            return (false, L10n.string("error.node_not_resolved"))
        }

        let actionArg = action == .clockIn ? "clock-in" : "clock-out"
        let cmd: [String: Any] = [
            "cmd": actionArg,
            "username": creds.username,
            "password": creds.password,
            "baseUrl": AppSettings.shared.effectiveKotBaseURL,
        ]
        var daemonOutput: String?
        daemonQueue.sync {
            if ensureDaemonRunning(automationDir: automationDir, cliURL: cliURL, nodePath: nodePath) {
                daemonOutput = sendDaemonCommandAndReadLine(command: cmd)
            }
        }
        if let line = daemonOutput,
           let data = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["ok"] as? Bool == true {
                return (true, "")
            }
            let err = json["error"] as? String ?? line
            let code = json["code"] as? String
            let output = code ?? err
            return (false, output)
        }

        // Don't start a second browser (one-shot) if the daemon is still running.
        var daemonRunning = false
        daemonQueue.sync { daemonRunning = daemonProcess?.isRunning == true }
        if daemonRunning {
            return (false, L10n.string("error.daemon_no_response"))
        }
        return runClockOneShot(automationDir: automationDir, cliURL: cliURL, nodePath: nodePath, action: action)
    }

    private func runClockOneShot(automationDir: URL, cliURL: URL, nodePath: String, action: ClockAction) -> (Bool, String) {
        guard let creds = CredentialsManager.shared.loadCredentials() else { return (false, "") }
        let actionArg = action == .clockIn ? "clock-in" : "clock-out"
        var env = ProcessInfo.processInfo.environment
        env["KOT_USERNAME"] = creds.username
        env["KOT_PASSWORD"] = creds.password
        env["KOT_BASE_URL"] = AppSettings.shared.effectiveKotBaseURL
        if AppEnvironment.isLocal { env["JOT_DEV"] = "1" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [cliURL.path, actionArg]
        process.currentDirectoryURL = automationDir
        process.environment = env
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !output.isEmpty {
                for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
                    AppLogger.info("Automation: \(line)")
                }
            }
            return (process.terminationStatus == 0, output)
        } catch {
            AppLogger.error("Automation: failed to run: \(error.localizedDescription)")
            return (false, "")
        }
    }

    /// Run timecard-status and return parsed payload. Completion on background thread.
    func runTimecardStatus(completion: @escaping (Result<TimecardStatusPayload, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            completion(self.runTimecardStatusSync())
        }
    }

    /// Cheap reachability probe for the configured KOT base URL so we can fail fast with a clear reason before spinning up Playwright.
    /// - Parameter networkConnected: When provided (e.g. from preflight context), use this instead of PreflightState so we don't rely on async state that may lag when coming back online.
    func quickSiteReachabilityCheck(networkConnected: Bool? = nil) -> Bool {
        let connected = networkConnected ?? PreflightState.shared.networkConnected
        if !connected {
            AppLogger.verbose("Automation: timecard pre-check: network offline, treating site as unreachable")
            return false
        }

        let rawBase = AppSettings.shared.effectiveKotBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawBase.isEmpty {
            // Empty means "use default" — let automation handle it.
            return true
        }
        let urlString = rawBase.contains("://") ? rawBase : "https://" + rawBase
        guard let url = URL(string: urlString) else {
            AppLogger.error("Automation: timecard pre-check: invalid base URL \"\(rawBase)\"")
            return false
        }

        var reachable = false
        let semaphore = DispatchSemaphore(value: 0)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse {
                // Treat 2xx–4xx as "site reachable" — 5xx/absence/transport errors mean unreachable.
                reachable = (200..<500).contains(http.statusCode)
            }
            if let error = error {
                AppLogger.error("Automation: timecard pre-check: HEAD \(urlString) failed: \(error.localizedDescription)")
            }
            semaphore.signal()
        }.resume()

        if semaphore.wait(timeout: .now() + 4) == .timedOut {
            AppLogger.error("Automation: timecard pre-check: HEAD \(urlString) timed out")
            return false
        }
        return reachable
    }

    private func runTimecardStatusSync() -> Result<TimecardStatusPayload, Error> {
        AppLogger.info("Automation: CLI request: timecard-status")
        guard let automationDir = resolveAutomationDirectory(),
              let cliURL = cliURL(automationDir: automationDir) else {
            AppLogger.error("Automation: timecard: automation directory or cli.js not found")
            return .failure(NSError(domain: "AutomationInvoker", code: -1, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.automation_not_found")]))
        }
        guard let creds = CredentialsManager.shared.loadCredentials() else {
            AppLogger.error("Automation: timecard: no stored credentials")
            return .failure(NSError(domain: "AutomationInvoker", code: -1, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.no_credentials")]))
        }
        guard let nodePath = resolvedNodePath else {
            AppLogger.error("Automation: timecard: node path not resolved (run startup check first)")
            return .failure(NSError(domain: "AutomationInvoker", code: -1, userInfo: [
                NSLocalizedDescriptionKey: L10n.string("error.node_not_resolved"),
                "JOTErrorKind": "node_not_resolved"
            ]))
        }

        if !quickSiteReachabilityCheck() {
            AppLogger.error("Automation: timecard: base URL not reachable before timecard-status; skipping daemon")
            return .failure(NSError(domain: "AutomationInvoker", code: -1, userInfo: [
                NSLocalizedDescriptionKey: Self.networkErrorMessage
            ]))
        }

        let cmd: [String: Any] = [
            "cmd": "timecard-status",
            "username": creds.username,
            "password": creds.password,
            "baseUrl": AppSettings.shared.effectiveKotBaseURL,
        ]
        var daemonLine: String?
        daemonQueue.sync {
            if ensureDaemonRunning(automationDir: automationDir, cliURL: cliURL, nodePath: nodePath) {
                daemonLine = sendDaemonCommandAndReadLine(command: cmd)
            }
        }
        if let line = daemonLine, let jsonData = line.data(using: .utf8), !jsonData.isEmpty, line.hasPrefix("{") {
            if line.hasPrefix("{\"error\"") {
                if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let errorCode = json["error"] as? String, !errorCode.isEmpty {
                    let detail = json["message"] as? String
                    let reason: String
                    if let d = detail, !d.isEmpty {
                        reason = "\(errorCode): \(d)"
                    } else {
                        reason = errorCode
                    }
                    AppLogger.error("Automation: timecard daemon error: \(reason)")
                    return .failure(NSError(domain: "AutomationInvoker", code: -1, userInfo: [NSLocalizedDescriptionKey: reason]))
                }
            } else {
                do {
                    let payload = try JSONDecoder().decode(TimecardStatusPayload.self, from: jsonData)
                    AppLogger.info("Automation: timecard payload (daemon): shouldWorkToday=\(payload.shouldWorkToday), clockedIn=\(payload.clockedIn), clockInTime=\(payload.clockInTime ?? "nil"), clockedOut=\(payload.clockedOut), clockOutTime=\(payload.clockOutTime ?? "nil"), todayLabel=\(payload.todayLabel ?? "nil")")
                    return .success(payload)
                } catch {
                    AppLogger.error("Automation: timecard daemon decode failed: \(error.localizedDescription)")
                }
            }
        }

        // Don't start a second browser (one-shot) if the daemon is still running — we'd have two WebKit windows.
        var daemonRunning = false
        daemonQueue.sync { daemonRunning = daemonProcess?.isRunning == true }
        if daemonRunning {
            return .failure(NSError(domain: "AutomationInvoker", code: -1, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.daemon_no_timecard")]))
        }
        return runTimecardStatusOneShot(automationDir: automationDir, cliURL: cliURL, nodePath: nodePath, creds: creds)
    }

    private func runTimecardStatusOneShot(automationDir: URL, cliURL: URL, nodePath: String, creds: Credentials) -> Result<TimecardStatusPayload, Error> {
        var env = ProcessInfo.processInfo.environment
        env["KOT_USERNAME"] = creds.username
        env["KOT_PASSWORD"] = creds.password
        env["KOT_BASE_URL"] = AppSettings.shared.effectiveKotBaseURL
        if AppEnvironment.isLocal { env["JOT_DEV"] = "1" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [cliURL.path, "timecard-status"]
        process.currentDirectoryURL = automationDir
        process.environment = env
        let outputPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
            if !stderrStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                for line in stderrStr.split(separator: "\n", omittingEmptySubsequences: false) {
                    AppLogger.verbose("Automation: \(line)")
                }
            }
            guard process.terminationStatus == 0 else {
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                AppLogger.error("Automation: timecard process exited \(process.terminationStatus): \(output)")
                return .failure(NSError(domain: "AutomationInvoker", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output]))
            }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8) ?? ""
            var jsonLine = raw.split(separator: "\n", omittingEmptySubsequences: false)
                .lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasPrefix("{") && $0.hasSuffix("}") }
                ?? raw.trimmingCharacters(in: .whitespaces)
            if jsonLine.hasPrefix("\u{FEFF}") { jsonLine = String(jsonLine.dropFirst()) }
            guard let jsonData = jsonLine.data(using: .utf8), !jsonData.isEmpty else {
                AppLogger.error("Automation: timecard: no JSON in stdout")
                return .failure(NSError(domain: "AutomationInvoker", code: -1, userInfo: [NSLocalizedDescriptionKey: L10n.string("error.no_stdout")]))
            }
            let payload = try JSONDecoder().decode(TimecardStatusPayload.self, from: jsonData)
            AppLogger.info("Automation: timecard payload (one-shot): shouldWorkToday=\(payload.shouldWorkToday), clockedIn=\(payload.clockedIn), clockInTime=\(payload.clockInTime ?? "nil"), clockedOut=\(payload.clockedOut), clockOutTime=\(payload.clockOutTime ?? "nil"), todayLabel=\(payload.todayLabel ?? "nil")")
            return .success(payload)
        } catch {
            AppLogger.error("Automation: timecard one-shot failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Run at startup: prefer Homebrew node (real binary); fall back to shell's which node. Log path and version, store path for clock commands.
    func performStartupNodeCheck() -> Bool {
        let fm = FileManager.default
        let homebrewPaths = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        for path in homebrewPaths {
            if fm.isExecutableFile(atPath: path) {
                if let version = runNodeVersion(at: path) {
                    resolvedNodePath = path
                    resolvedNodeVersion = version
                    AppLogger.debug("Automation: startup: node path=\(path) version=\(version)")
                    return true
                }
            }
        }
        guard let automationDir = resolveAutomationDirectory() else {
            AppLogger.error("Automation: startup: automation directory not found")
            return false
        }
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l", "-c", "which node; node --version"]
        process.currentDirectoryURL = automationDir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            let path = lines.first.flatMap { $0.isEmpty ? nil : $0 }
            let version = lines.count > 1 ? lines[1] : nil
            if process.terminationStatus == 0, let path = path, !path.isEmpty {
                resolvedNodePath = path
                resolvedNodeVersion = version ?? runNodeVersion(at: path)
                AppLogger.debug("Automation: startup: node path=\(path) version=\(resolvedNodeVersion ?? "?")")
                return true
            }
            AppLogger.error("Automation: startup: node check failed (exit \(process.terminationStatus)) — \(output)")
            return false
        } catch {
            AppLogger.error("Automation: startup: could not run node check — \(error.localizedDescription)")
            return false
        }
    }

    /// Tell the automation to log "App started" in logs/clocker.log so each launch has a clear marker. Call after performStartupNodeCheck. No output needed.
    func runAppStartLog() {
        guard let automationDir = resolveAutomationDirectory(),
              let url = cliURL(automationDir: automationDir),
              let nodePath = resolvedNodePath else { return }
        var env = ProcessInfo.processInfo.environment
        if AppEnvironment.isLocal { env["JOT_DEV"] = "1" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [url.path, "app-start"]
        process.currentDirectoryURL = automationDir
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// Run node --version at the given path; returns version string or nil.
    private func runNodeVersion(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Resolve automation directory: app bundle Resources when built, or build/automation (dev) or repo root with dist/ (legacy).
    private func resolveAutomationDirectory() -> URL? {
        if let resources = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resources.appendingPathComponent("cli.js").path) {
            return resources
        }
        // Dev (yarn start): look for .dev/cli.js
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<10 {
            let devDir = dir.appendingPathComponent(".dev")
            let devCli = devDir.appendingPathComponent("cli.js")
            if fm.fileExists(atPath: devCli.path) {
                AppLogger.debug("Automation: dir (dev): \(devDir.path)")
                return devDir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        AppLogger.error("Automation: dir not found (searched from \(fm.currentDirectoryPath))")
        return nil
    }

    /// CLI path: automation/dist/cli.js (bundle) or automation/cli.js (dev build/automation).
    private func cliURL(automationDir: URL) -> URL? {
        let dist = automationDir.appendingPathComponent("dist/cli.js")
        if FileManager.default.fileExists(atPath: dist.path) { return dist }
        let flat = automationDir.appendingPathComponent("cli.js")
        if FileManager.default.fileExists(atPath: flat.path) { return flat }
        return nil
    }
}
