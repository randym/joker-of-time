import SwiftUI
import AppKit
import Foundation

// MARK: - Icon

enum PromptIcon {
    case symbol(String, Color)
    case symbolWithGradient(String, LinearGradient)
    
    @ViewBuilder
    var view: some View {
        switch self {
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
        case .symbolWithGradient(let name, let gradient):
            Image(systemName: name)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(gradient)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

// MARK: - Button Protocol

protocol PromptButton {
    static var label: String { get }
    static var notification: Notification.Name { get }
    static var keyboardShortcut: KeyboardShortcut? { get }
}

// MARK: - Content Protocol

protocol PromptContent {
    static var icon: PromptIcon { get }
    static var title: String { get }
    static var message: String { get }
    static var windowTitle: String { get }
    static var buttons: [any PromptButton.Type] { get }
    static func present()
}

extension PromptContent {
    static func present() {
        PromptPresenter.present(content: Self.self)
    }
}

// MARK: - Shared View

struct PromptView<Content: PromptContent>: View {
    let content: Content.Type
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon + title + message
            HStack(alignment: .top, spacing: 14) {
                Content.icon.view
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(Content.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(Content.message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 20)
            
            // Buttons
            HStack(spacing: 10) {
                Spacer()
                ForEach(Array(Content.buttons.enumerated()), id: \.offset) { index, buttonType in
                    let shortcut = buttonType.keyboardShortcut ?? .defaultAction

                    Button(buttonType.label) {
                        PromptPresenter.closeIfOpen()
                        NotificationCenter.default.post(name: buttonType.notification, object: nil)
                    }.keyboardShortcut(shortcut)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(.regularMaterial)
    }
}

// MARK: - Presenter

enum PromptPresenter {
    private static weak var currentPanel: NSPanel?
    
    /// Close the prompt panel if it is open. Call on main.
    static func closeIfOpen() {
        currentPanel?.close()
        currentPanel = nil
    }
    
    /// Present a prompt with the given content. Call on main.
    static func present<Content: PromptContent>(content: Content.Type) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = Content.windowTitle
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level.statusBar
        panel.hidesOnDeactivate = false
        panel.contentMinSize = NSSize(width: 420, height: 220)
        currentPanel = panel
        
        let view = PromptView(content: content)
        let hosting = NSHostingController(rootView: view)
        panel.contentViewController = hosting
        panel.center()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
