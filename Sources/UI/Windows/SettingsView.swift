import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var credentials = CredentialsManager.shared
    @State private var credentialsUsername: String = ""
    @State private var credentialsPassword: String = ""
    @State private var kotURLText: String = ""
    @FocusState private var urlFieldFocused: Bool
    @State private var nodePathText: String = ""
    @FocusState private var nodePathFieldFocused: Bool
    @FocusState private var credentialsUsernameFocused: Bool

    private var workdayHoursBinding: Binding<Double> {
        Binding(
            get: { settings.workdayHours },
            set: { newValue in
                let clamped = min(12, max(4, newValue))
                let rounded = (clamped * 2).rounded() / 2
                settings.workdayHours = rounded
                settings.save()
                SessionManager.shared.rescheduleTimersIfClockedIn()
            }
        )
    }

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
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("settings.title"))
                        .font(.title2)
                        .bold()
                    Text(L10n.string("settings.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Account (production + local)
                        GroupBox(L10n.string("settings.section.account")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.string("credentials.title"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(L10n.string("settings.credentials_help"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.string("credentials.login_id"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    TextField(L10n.string("credentials.login_id"), text: $credentialsUsername)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($credentialsUsernameFocused)
                                        .onChange(of: credentialsUsername) { _ in
                                            SettingsWindowController.shared.setCurrentCredentials(username: credentialsUsername, password: credentialsPassword)
                                        }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.string("credentials.password"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    SecureField(L10n.string("credentials.password"), text: $credentialsPassword, prompt: Text(credentials.hasStoredCredentials ? L10n.string("credentials.masked") : L10n.string("credentials.password")))
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: credentialsPassword) { _ in
                                            SettingsWindowController.shared.setCurrentCredentials(username: credentialsUsername, password: credentialsPassword)
                                        }
                                }
                                if let status = credentials.keychainErrorMessage {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onAppear {
                                if let creds = CredentialsManager.shared.loadCredentials() {
                                    credentialsUsername = creds.username
                                }
                                credentialsPassword = ""
                                SettingsWindowController.shared.setCurrentCredentials(username: credentialsUsername, password: credentialsPassword)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("credentialsSection")

                        // Automation (production + local)
                        GroupBox(L10n.string("settings.section.automation")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.string("settings.hours_per_day"))
                                    .font(.subheadline)
                                HStack(alignment: .center, spacing: 8) {
                                    Text(L10n.string("format.hours", settings.workdayHours))
                                        .frame(minWidth: 36, alignment: .trailing)
                                    Stepper("", value: workdayHoursBinding, in: 4...12, step: 0.5)
                                }
                                Text(L10n.string("settings.workday_help"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // App (production + local)
                        GroupBox(L10n.string("settings.section.app")) {
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: Binding(
                                    get: { settings.runOnLogin },
                                    set: { newValue in
                                        settings.runOnLogin = newValue
                                        settings.save()
                                        if !AppEnvironment.isLocal {
                                            LoginItemManager.shared.setEnabled(newValue)
                                        }
                                    }
                                )) {
                                    Text(L10n.string("settings.launch_at_login"))
                                }
                                Text(L10n.string("settings.launch_at_login_help"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if AppEnvironment.isLocal {
                            GroupBox(L10n.string("settings.kot")) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(L10n.string("settings.url"))
                                        .font(.subheadline)
                                    TextField(L10n.string("settings.url"), text: $kotURLText)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($urlFieldFocused)
                                        .onChange(of: kotURLText) { newValue in
                                            SettingsWindowController.shared.setCurrentURLString(newValue)
                                            settings.kotBaseURL = newValue
                                            settings.save()
                                        }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("urlSection")

                            GroupBox(L10n.string("settings.node")) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(L10n.string("settings.node_path"))
                                        .font(.subheadline)
                                    TextField(L10n.string("settings.node_path"), text: $nodePathText)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($nodePathFieldFocused)
                                        .onChange(of: nodePathText) { newValue in
                                            settings.nodePath = newValue
                                            settings.save()
                                            _ = AutomationInvoker.shared.performStartupNodeCheck()
                                        }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("nodePathSection")

                            GroupBox(L10n.string("settings.diagnostics")) {
                                Picker(L10n.string("settings.log_level"), selection: Binding(
                                    get: { settings.logLevel },
                                    set: { newValue in
                                        settings.logLevel = newValue
                                        settings.save()
                                    }
                                )) {
                                    ForEach(LogLevel.allCases) { level in
                                        Text(L10n.string("settings.log_level.\(level.rawValue)")).tag(level)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .onReceive(NotificationCenter.default.publisher(for: .settingsFocusNodePathField)) { _ in
                        nodePathFieldFocused = true
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("nodePathSection") }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .settingsFocusCredentialsField)) { _ in
                        credentialsUsernameFocused = true
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("credentialsSection") }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n.string("settings.close")) {
                    AppLogger.info("User: Settings Close tapped")
                    if AppEnvironment.isLocal {
                        SettingsWindowController.shared.setCurrentURLString(kotURLText)
                    }
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
                .padding(12)
                .padding(.trailing, 12)
            }
        }
        .frame(minWidth: 480, minHeight: 380)
        .onAppear {
            if let creds = CredentialsManager.shared.loadCredentials() {
                credentialsUsername = creds.username
            }
            credentialsPassword = ""
            SettingsWindowController.shared.setCurrentCredentials(username: credentialsUsername, password: credentialsPassword)
            if AppEnvironment.isLocal {
                kotURLText = settings.kotBaseURL
                SettingsWindowController.shared.setCurrentURLString(settings.kotBaseURL)
                nodePathText = settings.nodePath.isEmpty ? (AutomationInvoker.shared.resolvedNodePath ?? "") : settings.nodePath
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsFocusURLField)) { _ in
            guard AppEnvironment.isLocal else { return }
            urlFieldFocused = true
        }
    }
}

