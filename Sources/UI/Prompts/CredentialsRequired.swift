import Foundation
import SwiftUI

struct CredentialsRequired: PromptContent {
    static let icon: PromptIcon = .symbol("person.crop.circle.badge.plus", .secondary)
    static let title: String = L10n.string("alert.credentials_required.title")
    static let message: String = L10n.string("alert.credentials_required.message")
    static let windowTitle: String = L10n.string("window.title")
    
    private struct GoToSettingsButton: PromptButton {
        static let label: String = L10n.string("alert.go_to_settings")
        static let notification: Notification.Name = .promptCredentialsRequiredGoToSettings
        static let keyboardShortcut: KeyboardShortcut? = nil
        static let role: ButtonRole? = nil
    }
    
    static let buttons: [any PromptButton.Type] = [GoToSettingsButton.self]
}
