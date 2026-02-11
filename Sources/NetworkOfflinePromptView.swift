import SwiftUI
import AppKit

// MARK: - View (matches Start Work / Stop Work style: window, title, icon, message, button bottom right)

struct NetworkOfflinePromptView: View {
    let title: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 20)

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.string("alert.ok")) {
                    dismiss()
                }
                .buttonStyle(NetworkOfflineButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(.regularMaterial)
    }
}

private struct NetworkOfflineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Presenter (used by SessionManager)

enum NetworkOfflinePromptPresenter {
    private static weak var currentPanel: NSPanel?

    /// Close the panel if it is open. Call on main.
    static func closeIfOpen() {
        currentPanel?.close()
        currentPanel = nil
    }

    /// Present the network-offline prompt. Uses localized title and message. Call on main.
    static func present(onDismiss: @escaping () -> Void = {}) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.string("window.title")
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level.statusBar
        panel.hidesOnDeactivate = false
        currentPanel = panel

        let dismiss: () -> Void = { [weak panel] in
            panel?.close()
            if currentPanel === panel { currentPanel = nil }
            onDismiss()
        }

        let view = NetworkOfflinePromptView(
            title: L10n.string("alert.network_offline.title"),
            message: L10n.string("alert.network_offline.message"),
            dismiss: dismiss
        )

        let hosting = NSHostingController(rootView: view)
        panel.contentViewController = hosting
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(panel)
    }
}
