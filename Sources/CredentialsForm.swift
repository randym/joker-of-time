import SwiftUI
import AppKit

struct CredentialsForm: View {
    @ObservedObject private var credentials = CredentialsManager.shared
    @FocusState private var isLoginFocused: Bool
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var statusMessage: String?

    private var appIcon: NSImage? {
        var icon: NSImage?
        if let url = Bundle.main.url(forResource: "JokerOfTime", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { icon = img }
        if icon == nil, AppEnvironment.isLocal {
            let devPaths = [
                FileManager.default.currentDirectoryPath + "/assets/JokerOfTime.icns",
                (Bundle.main.bundlePath as NSString).deletingLastPathComponent + "/../../assets/JokerOfTime.icns",
            ]
            for p in devPaths {
                let url = URL(fileURLWithPath: (p as NSString).standardizingPath)
                if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                    icon = img
                    break
                }
            }
        }
        if icon == nil { icon = NSImage(named: "JokerOfTime") ?? NSImage(named: "AppIcon") }
        return icon ?? NSApplication.shared.applicationIconImage
    }

    private let headerIconSize: CGFloat = 48

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                if let img = appIcon {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: headerIconSize, height: headerIconSize)
                        .clipShape(RoundedRectangle(cornerRadius: headerIconSize * 0.2237))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("credentials.title"))
                        .font(.title2)
                        .bold()
                    Text(L10n.string("credentials.explanation"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.string("credentials.login_id"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField(L10n.string("credentials.login_id"), text: $username)
                                .textFieldStyle(.roundedBorder)
                                .focused($isLoginFocused)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.string("credentials.password"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            SecureField(L10n.string("credentials.password"), text: $password, prompt: Text(credentials.hasStoredCredentials ? L10n.string("credentials.masked") : L10n.string("credentials.password")))
                                .textFieldStyle(.roundedBorder)
                        }

                        if let status = statusMessage ?? credentials.keychainErrorMessage {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle((statusMessage == L10n.string("credentials.saved") || statusMessage == L10n.string("credentials.cleared")) ? Color.primary : Color.red)
                        }
                    }
                    .padding(4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            HStack {
                Spacer()
                Button(L10n.string("credentials.close")) {
                    tryCloseCredentialsWindow()
                }
                .keyboardShortcut(.cancelAction)
                Button(L10n.string("credentials.save")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            }
            .padding(12)
            .padding(.trailing, 12)
        }
        .frame(minWidth: 400)
        .onAppear {
            if let creds = CredentialsManager.shared.loadCredentials() {
                username = creds.username
            }
            // Defer focus so the window is key and the field can accept first responder (e.g. when form opens at startup).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isLoginFocused = true
            }
        }
    }

    private func save() {
        let user = username.trimmingCharacters(in: .whitespaces)
        if user.isEmpty || password.isEmpty {
            statusMessage = L10n.string("credentials.enter_login_password")
            return
        }
        statusMessage = nil
        let ok = CredentialsManager.shared.saveCredentials(username: user, password: password)
        if ok {
            statusMessage = L10n.string("credentials.saved")
            NotificationCenter.default.post(name: .closeCredentialsWindow, object: nil)
        } else {
            statusMessage = credentials.keychainErrorMessage ?? L10n.string("credentials.failed_to_save")
        }
    }

    private func tryCloseCredentialsWindow() {
        NotificationCenter.default.post(name: .closeCredentialsWindow, object: nil)
    }
}
