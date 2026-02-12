import Foundation
import SwiftUI

struct AlreadyClockedIn: PromptContent {
    static let icon: PromptIcon = .symbolWithGradient(
        "checkmark.circle.fill",
        LinearGradient(
            colors: [Color.green, Color(red: 0.2, green: 0.8, blue: 0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    static let title: String = L10n.string("alert.already_clocked_in.title")
    static let message: String = L10n.string("alert.already_clocked_in.message")
    static let windowTitle: String = L10n.string("window.title")
    
    private struct DismissButton: PromptButton {
        static let label: String = L10n.string("alert.ok")
        static let notification: Notification.Name = .promptAlreadyClockedInDismiss
        static let keyboardShortcut: KeyboardShortcut? = nil
    }
    
    static let buttons: [any PromptButton.Type] = [DismissButton.self]
}
