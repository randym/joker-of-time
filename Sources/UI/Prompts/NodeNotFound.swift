import Foundation
import SwiftUI

struct NodeNotFound: PromptContent {
    static let icon: PromptIcon = .symbol("circle.slash", .secondary)
    static let title: String = L10n.string("alert.node_not_found.title")
    static let message: String = L10n.string("alert.node_not_found.message")
    static let windowTitle: String = L10n.string("window.title")
    private struct DismissButton: PromptButton {
        static let label: String = L10n.string("alert.ok")
        static let notification: Notification.Name = .promptNodeNotFoundDismiss
        static let keyboardShortcut: KeyboardShortcut? = nil
    }
    
    static let buttons: [any PromptButton.Type] = [DismissButton.self]
}
