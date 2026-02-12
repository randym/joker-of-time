import Foundation
import SwiftUI

struct StopWorkOnTime: PromptContent {
    static let icon: PromptIcon = .symbolWithGradient(
        "questionmark.circle.fill",
        LinearGradient(
            colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    static let title: String = L10n.string("stop_work.confirm.title")
    static let message: String = L10n.string("stop_work.confirm.message")
    static let windowTitle: String = L10n.string("window.clock_out")
    private struct KeepWorkingButton: PromptButton {
        static let label: String = L10n.string("button.no_keep_working")
        static let notification: Notification.Name = .promptStopWorkKeepWorking
        static let keyboardShortcut: KeyboardShortcut? = .cancelAction
        static let role: ButtonRole? = .cancel
    }
    
    private struct ClockOutButton: PromptButton {
        static let label: String = L10n.string("button.yes_clock_out")
        static let notification: Notification.Name = .promptStopWorkClockOut
        static let keyboardShortcut: KeyboardShortcut? = .defaultAction
        static let role: ButtonRole? = nil
    }
    
    static let buttons: [any PromptButton.Type] = [KeepWorkingButton.self, ClockOutButton.self]
}
