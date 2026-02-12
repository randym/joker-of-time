import Foundation
import Network

/// Observes network path and posts a notification when connectivity changes. Use for preflight and graceful handling (e.g. show "Offline", retry when back online).
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Notification when path status changes. userInfo["isConnected"] = Bool. Posted on main queue.
    static let connectivityDidChangeNotification = Notification.Name("NetworkConnectivityDidChange")

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "io.github.randym.JokerOfTime.network")

    /// True when the current path is satisfied (network available). Updates on path changes; read from any thread.
    private(set) var isConnected: Bool = true {
        didSet {
            if oldValue != isConnected {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    AppLogger.info("Network: \(self.isConnected ? "connected" : "offline")")
                    NotificationCenter.default.post(
                        name: Self.connectivityDidChangeNotification,
                        object: self,
                        userInfo: ["isConnected": self.isConnected]
                    )
                }
            }
        }
    }

    private init() {
        monitor = NWPathMonitor()
    }

    /// Start observing. Call once at launch (e.g. from AppDelegate).
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = (path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }
}
