import Foundation
import SwiftUI

struct NotClockedIn: PromptContent {
    static let icon: PromptIcon = .symbolWithGradient(
        "exclamationmark.triangle.fill",
        LinearGradient(
            colors: [Color.yellow, Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    static let title: String = L10n.string("alert.cannot_clock_out.title")
    static let message: String = L10n.string("alert.cannot_clock_out.not_clocked_in")
    static let windowTitle: String = L10n.string("window.title")
    private struct DismissButton: PromptButton {
        static let label: String = L10n.string("alert.ok")
        static let notification: Notification.Name = .promptNotClockedInDismiss
        static let keyboardShortcut: KeyboardShortcut? = nil
        static let role: ButtonRole? = nil
    }
    
    static let buttons: [any PromptButton.Type] = [DismissButton.self]
}
