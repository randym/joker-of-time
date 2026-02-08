import SwiftUI
import AppKit

// MARK: - Copy with personality (MOTD-style: rotates by day so it’s stable but not the same forever)


private func startWorkMessageForToday() -> (title: String, subtitle: String) {
    let keys = ["start_work.msg0", "start_work.msg1", "start_work.msg2", "start_work.msg3", "start_work.msg4", "start_work.msg5"]
    let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
    let base = keys[day % keys.count]
    return (L10n.string("\(base).title"), L10n.string("\(base).subtitle"))
}

// MARK: - Custom Start Work dialog (replaces the boring NSAlert)

struct StartWorkPromptView: View {
    let message: (title: String, subtitle: String)
    let dismiss: () -> Void
    let onYes: () -> Void
    let onNo: (Bool) -> Void

    @State private var dontAskAgainToday = false

    init(
        message: (title: String, subtitle: String)? = nil,
        dismiss: @escaping () -> Void,
        onYes: @escaping () -> Void,
        onNo: @escaping (Bool) -> Void
    ) {
        self.message = message ?? startWorkMessageForToday()
        self.dismiss = dismiss
        self.onYes = onYes
        self.onNo = onNo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon + title block
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.3, green: 0.6, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 6) {
                    Text(message.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(message.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 18)

            // Don’t ask again
            Toggle(isOn: $dontAskAgainToday) {
                Text(L10n.string("start_work.dont_ask_again"))
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .padding(.bottom, 18)

            // Buttons
            HStack(spacing: 10) {
                Spacer()
                Button(L10n.string("button.no")) {
                    dismiss()
                    onNo(dontAskAgainToday)
                }
                .buttonStyle(StartWorkButtonStyle(isPrimary: false))

                Button(L10n.string("button.yes")) {
                    dismiss()
                    onYes()
                }
                .buttonStyle(StartWorkButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(.regularMaterial)
    }
}

private struct StartWorkButtonStyle: ButtonStyle {
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

// MARK: - Panel presenter (used by SessionManager)

enum StartWorkPromptPresenter {
    private static weak var currentPanel: NSPanel?

    /// Close the start-work panel if it is open (e.g. when credentials are cleared). Call on main.
    static func closeIfOpen() {
        currentPanel?.close()
        currentPanel = nil
    }

    /// Present the Start Work dialog. Callbacks run on main; dismiss closes the panel.
    static func present(onYes: @escaping () -> Void, onNo: @escaping (Bool) -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.string("window.clock_in")
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level.statusBar
        panel.hidesOnDeactivate = false
        currentPanel = panel

        let dismiss: () -> Void = { [weak panel] in
            panel?.close()
            if currentPanel === panel { currentPanel = nil }
        }

        let view = StartWorkPromptView(
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
