import Foundation
import SwiftUI

struct SomethingWentWrong: PromptContent {
    static let icon: PromptIcon = .symbolWithGradient(
        "exclamationmark.triangle.fill",
        LinearGradient(
            colors: [Color.red, Color(red: 0.8, green: 0.1, blue: 0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    static let title: String = L10n.string("alert.something_wrong.title")
    static let message: String = L10n.string("alert.something_wrong.message")
    static let windowTitle: String = L10n.string("window.title")
    private struct DismissButton: PromptButton {
        static let label: String = L10n.string("alert.ok")
        static let notification: Notification.Name = .promptSomethingWentWrongDismiss
        static let keyboardShortcut: KeyboardShortcut? = nil
    }
    
    static let buttons: [any PromptButton.Type] = [DismissButton.self]
}
