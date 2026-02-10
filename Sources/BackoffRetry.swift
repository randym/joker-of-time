import Foundation

/// A single run of work that can succeed or fail. Used with `BackoffRetryRunner` for retry-with-backoff.
protocol RetryableCommand {
    /// Execute the operation. Return success or failure (e.g. network unreachable).
    func execute() -> Result<Void, Error>
}

/// Runs a command with Fibonacci backoff: try immediately, then after 1s, 1s, 2s, 3s, … between attempts.
/// Use for network-style work where transient failures are common.
enum BackoffRetryRunner {
    /// Hardcoded Fibonacci delays in seconds (1, 1, 2, 3) before each retry. Max 4 retries (5 attempts total; ~7s of backoff).
    private static let fibDelaysSeconds: [Int] = [1, 1, 2, 3]

    /// Run `command` up to 5 times (1 initial + 4 retries). Delays between retries: 1s, 1s, 2s, 3s.
    /// On first success, calls `completion(.success(()))`. After final failure, calls `completion(.failure(lastError))`.
    static func run(
        command: RetryableCommand,
        queue: DispatchQueue = .main,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let maxAttempts = 5
        var attempt = 0
        func tryOnce() {
            attempt += 1
            let result = command.execute()
            switch result {
            case .success:
                AppLogger.debug("BackoffRetry: succeeded on attempt \(attempt)")
                completion(.success(()))
            case .failure(let error):
                if attempt >= maxAttempts {
                    AppLogger.debug("BackoffRetry: failed after \(maxAttempts) attempts")
                    completion(.failure(error))
                    return
                }
                let delay = Self.fibDelaysSeconds[attempt - 1]
                AppLogger.debug("BackoffRetry: attempt \(attempt) failed, retrying in \(delay)s")
                queue.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(delay)) {
                    tryOnce()
                }
            }
        }
        queue.async { tryOnce() }
    }
}
