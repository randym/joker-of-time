import Foundation
import SwiftUI

struct StartWork: PromptContent {
    static let icon: PromptIcon = .symbolWithGradient(
        "clock.badge.checkmark",
        LinearGradient(
            colors: [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.3, green: 0.6, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    static let title: String = L10n.string("start_work.msg3.title")
    static let message: String = L10n.string("start_work.msg3.subtitle")
    static let windowTitle: String = L10n.string("window.clock_in")
    private struct DismissButton: PromptButton {
        static let label: String = L10n.string("start_work.dismiss")
        static let notification: Notification.Name = .promptStartWorkDismiss
        static let keyboardShortcut: KeyboardShortcut? = .cancelAction
    }
    
    private struct ClockInButton: PromptButton {
        static let label: String = L10n.string("start_work.clock_in")
        static let notification: Notification.Name = .promptStartWorkClockIn
        static let keyboardShortcut: KeyboardShortcut? = .defaultAction
    }
    
    static let buttons: [any PromptButton.Type] = [DismissButton.self, ClockInButton.self]
}
