import Foundation

protocol RetryableCommand {
    func execute() -> Result<Void, Error>
}

enum BackoffRetryRunner {
    private static let fibDelaysSeconds: [Int] = [1, 1, 2, 3, 5]
    static func run(
        command: RetryableCommand,
        queue: DispatchQueue = .main,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let maxAttempts = 6
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
