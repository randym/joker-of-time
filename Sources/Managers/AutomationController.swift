import Foundation
import Combine

/// High-level automation entrypoint for the app. All automation flows
/// (startup resync, auto-resync, manual Sync, Clock In, Clock Out) should
/// eventually route through this controller.
enum AutomationCommandKind {
    case resync
    case clockIn
    case clockOut
}

enum AutomationErrorKind {
    case preflight
    case node
    case busy
}

struct AutomationError {
    let kind: AutomationErrorKind
    let code: String
    let message: String
}

enum AutomationEvent {
    case started(kind: AutomationCommandKind)
    case succeeded(kind: AutomationCommandKind, payload: TimecardStatusPayload?)
    case failed(kind: AutomationCommandKind, error: AutomationError)
    case busy(kind: AutomationCommandKind)
}

/// Initial, behavior-preserving façade: delegate to existing functions.
/// Later phases will move logic into command types and events.
final class AutomationController {
    static let shared = AutomationController()

    /// Event stream for all automation activity. In early phases this is a
    /// mirror of existing behavior; later phases will drive SessionManager/UI
    /// directly from these events.
    let events = PassthroughSubject<AutomationEvent, Never>()

    private var currentCommand: AutomationCommandKind?

    private init() {}

    enum ResyncSource {
        case startup
        case wake
        case network
        case settingsClose
        case manual
    }

    /// Single-flight guard: ensure only one automation command runs at a time.
    /// On contention, emit a BUSY event and return false.
    private func beginCommand(_ kind: AutomationCommandKind) -> Bool {
        if currentCommand != nil {
            AppLogger.info("AutomationController: \(kind) requested but \(String(describing: currentCommand)) already running; reporting busy")
            events.send(.busy(kind: kind))
            return false
        }
        AppLogger.info("AutomationController: starting \(kind)")
        currentCommand = kind
        events.send(.started(kind: kind))
        return true
    }

    private func endCommand() {
        currentCommand = nil
    }

    /// Shared handler for command results: map Result into events and, if the error
    /// comes from preflight, route through PreflightUIHandler using the provided
    /// preflight UI context.
    private func handleCommandResult(
        kind: AutomationCommandKind,
        preflightContext: PreflightUIContext,
        result: Result<Void, Error>
    ) {
        switch result {
        case .success:
            AppLogger.info("AutomationController: \(kind) succeeded")
            events.send(.succeeded(kind: kind, payload: nil))

        case .failure(let error):
            if let preflightErr = error as? PreflightFailureError {
                let failure = preflightErr.failure
                AppLogger.info("AutomationController: \(kind) failed with preflight \(failure.kind) reasonKey=\(failure.reasonKey)")
                let automationError = AutomationError(
                    kind: .preflight,
                    code: failure.reasonKey,
                    message: failure.reasonKey
                )
                events.send(.failed(kind: kind, error: automationError))
                PreflightUIHandler.handleFailure(failure, context: preflightContext)
            } else {
                AppLogger.error("AutomationController: \(kind) failed with node error: \(error.localizedDescription)")
                let code: String
                switch kind {
                case .resync:
                    code = "resync_failed"
                case .clockIn:
                    code = "clockIn_failed"
                case .clockOut:
                    code = "clockOut_failed"
                }
                let automationError = AutomationError(
                    kind: .node,
                    code: code,
                    message: error.localizedDescription
                )
                events.send(.failed(kind: kind, error: automationError))
            }
        }
        endCommand()
    }

    /// Shared runner for ResyncCommand with backoff.
    private func runResyncWithBackoff(
        context: PreflightUIContext,
        uiContext: PreflightUIContext
    ) {
        BackoffRetryRunner.run(command: ResyncCommand(context: context)) { result in
            self.handleCommandResult(kind: .resync, preflightContext: uiContext, result: result)
        }
    }

    /// Request a resync of the timecard / session state.
    func requestResync(source: ResyncSource) {
        guard beginCommand(.resync) else { return }
        switch source {
        case .startup:
            runResyncWithBackoff(context: .startup, uiContext: .startup)

        case .wake:
            runResyncWithBackoff(context: .autoResync, uiContext: .autoResync)

        case .network:
            runResyncWithBackoff(context: .autoResync, uiContext: .autoResync)

        case .settingsClose:
            runResyncWithBackoff(context: .settingsClose, uiContext: .settingsClose)

        case .manual:
            // Manual Sync from the menu: run preflight first, then refresh timecard.
            // If preflight fails, end the command so other automations aren't blocked.
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = PreflightRunner.runPreflightOutcome()
                DispatchQueue.main.async {
                    if outcome.success {
                        SessionManager.shared.recheckTimecardStatus()
                        self.endCommand()
                    } else {
                        if let failure = outcome.failure {
                            PreflightUIHandler.handleFailure(failure, context: .manualSync)
                        }
                        self.endCommand()
                    }
                }
            }
        }
    }

    /// Request a Clock In operation initiated by the user.
    /// Runs preflight first; only proceeds if preflight passes and no other command is running.
    func requestClockIn() {
        AppLogger.info("AutomationController: clockIn requested — running preflight")
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = PreflightRunner.runPreflightOutcome()
            DispatchQueue.main.async {
                guard outcome.success else {
                    if let failure = outcome.failure {
                        PreflightUIHandler.handleFailure(failure, context: .manualSync)
                    }
                    return
                }
                guard self.beginCommand(.clockIn) else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = ClockInCommand().execute()
                    DispatchQueue.main.async {
                        self.handleCommandResult(kind: .clockIn, preflightContext: .manualSync, result: result)
                    }
                }
            }
        }
    }

    /// Request a Clock Out operation initiated by the user.
    /// Runs preflight first; only proceeds if preflight passes and no other command is running.
    func requestClockOut() {
        AppLogger.info("AutomationController: clockOut requested — running preflight")
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = PreflightRunner.runPreflightOutcome()
            DispatchQueue.main.async {
                guard outcome.success else {
                    if let failure = outcome.failure {
                        PreflightUIHandler.handleFailure(failure, context: .manualSync)
                    }
                    return
                }
                guard self.beginCommand(.clockOut) else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = ClockOutCommand().execute()
                    DispatchQueue.main.async {
                        self.handleCommandResult(kind: .clockOut, preflightContext: .manualSync, result: result)
                    }
                }
            }
        }
    }
}

