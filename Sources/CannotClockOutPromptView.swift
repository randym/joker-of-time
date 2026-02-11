import SwiftUI
import AppKit

// MARK: - View (yellow warning — cannot clock out: not clocked in, or already clocked out)

struct CannotClockOutPromptView: View {
    let title: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.yellow)

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
                .buttonStyle(CannotClockOutButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(.regularMaterial)
    }
}

private struct CannotClockOutButtonStyle: ButtonStyle {
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

enum CannotClockOutPromptPresenter {
    private static weak var currentPanel: NSPanel?

    /// Close the panel if it is open. Call on main.
    static func closeIfOpen() {
        currentPanel?.close()
        currentPanel = nil
    }

    /// Present the Cannot clock out prompt. Message varies (not clocked in vs already clocked out). Call on main.
    static func present(message: String, onDismiss: @escaping () -> Void = {}) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
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

        let view = CannotClockOutPromptView(
            title: L10n.string("alert.cannot_clock_out.title"),
            message: message,
            dismiss: dismiss
        )

        let hosting = NSHostingController(rootView: view)
        panel.contentViewController = hosting
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(panel)
    }
}
