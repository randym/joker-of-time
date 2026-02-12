import Foundation
import SwiftUI

struct NetworkOffline: PromptContent {
    static let icon: PromptIcon = .symbolWithGradient(
        "wifi.exclamationmark",
        LinearGradient(
            colors: [Color.blue.opacity(0.6), Color.gray],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    static let title: String = L10n.string("alert.network_offline.title")
    static let message: String = L10n.string("alert.network_offline.message")
    static let windowTitle: String = L10n.string("window.title")
    private struct DismissButton: PromptButton {
        static let label: String = L10n.string("alert.ok")
        static let notification: Notification.Name = .promptNetworkOfflineDismiss
        static let keyboardShortcut: KeyboardShortcut? = nil
    }
    
    static let buttons: [any PromptButton.Type] = [DismissButton.self]
}
