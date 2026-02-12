import Foundation
import SwiftUI

struct LoginFailed: PromptContent {
    static let icon: PromptIcon = .symbolWithGradient(
        "key.slash",
        LinearGradient(
            colors: [Color.red.opacity(0.8), Color(red: 0.7, green: 0.1, blue: 0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    static let title: String = L10n.string("alert.login_failed.title")
    static let message: String = L10n.string("alert.login_failed.message")
    static let windowTitle: String = L10n.string("window.title")
    private struct DismissButton: PromptButton {
        static let label: String = L10n.string("alert.ok")
        static let notification: Notification.Name = .promptLoginFailedDismiss
        static let keyboardShortcut: KeyboardShortcut? = nil
    }
    
    static let buttons: [any PromptButton.Type] = [DismissButton.self]
}
