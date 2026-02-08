import SwiftUI
import AppKit

struct StopWorkPromptView: View {
    let title: String
    let message: String
    let isCritical: Bool
    let dismiss: () -> Void
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isCritical ? "clock.badge.questionmark" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(isCritical ? Color.orange : Color.red)
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
                Button(L10n.string("button.no_keep_working")) {
                    dismiss()
                    onNo()
                }
                .buttonStyle(StopWorkButtonStyle(isPrimary: !isCritical))
                .keyboardShortcut(isCritical ? .cancelAction : .defaultAction)

                Button(L10n.string("button.yes_clock_out")) {
                    dismiss()
                    onYes()
                }
                .buttonStyle(StopWorkButtonStyle(isPrimary: isCritical))
                .keyboardShortcut(isCritical ? .defaultAction : .cancelAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

private struct StopWorkButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPrimary ? Color.accentColor : Color(white: 0.85))
            )
            .foregroundStyle(isPrimary ? .white : .primary)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

enum StopWorkPromptPresenter {
    private static weak var currentPanel: NSPanel?

    /// Close the stop-work panel if it is open (e.g. when credentials are cleared). Call on main.
    static func closeIfOpen() {
        currentPanel?.close()
        currentPanel = nil
    }

    /// Present the Stop Work dialog. Callbacks run on main; dismiss closes the panel.
    static func present(
        title: String,
        message: String,
        isCritical: Bool,
        onYes: @escaping () -> Void,
        onNo: @escaping () -> Void
    ) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.string("window.clock_out")
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level.statusBar
        panel.hidesOnDeactivate = false
        currentPanel = panel

        let dismiss: () -> Void = { [weak panel] in
            panel?.close()
            if currentPanel === panel { currentPanel = nil }
        }

        let view = StopWorkPromptView(
            title: title,
            message: message,
            isCritical: isCritical,
            dismiss: dismiss,
            onYes: onYes,
            onNo: onNo
        )

        let hosting = NSHostingController(rootView: view)
        panel.contentViewController = hosting
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(panel)
    }
}
