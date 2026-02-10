import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var credentials = CredentialsManager.shared
    @State private var credentialsUsername: String = ""
    @State private var credentialsPassword: String = ""
    @State private var credentialsStatusMessage: String?
    @State private var kotURLText: String = ""
    @State private var urlValidationMessage: String?
    @FocusState private var urlFieldFocused: Bool

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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox(L10n.string("settings.kot")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("settings.url"))
                                .font(.subheadline)

                            TextField(
                                L10n.string("settings.url"),
                                text: $kotURLText
                            )
                            .textFieldStyle(.roundedBorder)
                            .focused($urlFieldFocused)
                            .onChange(of: kotURLText) { newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                let msg = AppSettings.kotURLValidationError(trimmed: trimmed)
                                urlValidationMessage = msg
                                SettingsWindowController.shared.setCurrentURLString(trimmed)
                                if msg != nil { return }
                                if trimmed.isEmpty { return }
                                settings.kotBaseURL = trimmed
                                settings.save()
                            }

                            if let msg = urlValidationMessage {
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            HStack(spacing: 8) {
                                Button(L10n.string("settings.open_in_browser")) {
                                    AppLogger.info("User: Settings open in browser")
                                    let base = settings.effectiveKotBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let urlString = base.contains("://") ? base : "https://" + base
                                    if let url = URL(string: urlString) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                                Button(L10n.string("settings.use_default_url")) {
                                    AppLogger.info("User: Settings use default URL")
                                    kotURLText = ""
                                    settings.kotBaseURL = ""
                                    settings.save()
                                    urlValidationMessage = nil
                                }
                                .buttonStyle(.bordered)
                            }

                            Text(L10n.string("settings.url_help"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.string("settings.example"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(L10n.string("settings.example_url"))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }

                            Text(L10n.string("settings.url_tip"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GroupBox(L10n.string("credentials.title")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("settings.credentials_help"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.string("credentials.login_id"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField(L10n.string("credentials.login_id"), text: $credentialsUsername)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.string("credentials.password"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                SecureField(L10n.string("credentials.password"), text: $credentialsPassword, prompt: Text(credentials.hasStoredCredentials ? L10n.string("credentials.masked") : L10n.string("credentials.password")))
                                    .textFieldStyle(.roundedBorder)
                            }

                            if let status = credentialsStatusMessage ?? credentials.keychainErrorMessage {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(status == L10n.string("credentials.saved") ? Color.primary : Color.red)
                            }

                            HStack(spacing: 8) {
                                Button(L10n.string("credentials.save")) {
                                    AppLogger.info("User: Settings save credentials")
                                    let user = credentialsUsername.trimmingCharacters(in: .whitespaces)
                                    if user.isEmpty || credentialsPassword.isEmpty {
                                        credentialsStatusMessage = L10n.string("credentials.enter_login_password")
                                        return
                                    }
                                    credentialsStatusMessage = nil
                                    if CredentialsManager.shared.saveCredentials(username: user, password: credentialsPassword) {
                                        credentialsStatusMessage = L10n.string("credentials.saved")
                                        SessionManager.shared.clearSessionStateForNewCredentials()
                                        DispatchQueue.main.async { runTimeCardTask() }
                                    } else {
                                        credentialsStatusMessage = credentials.keychainErrorMessage ?? L10n.string("credentials.failed_to_save")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(credentialsUsername.trimmingCharacters(in: .whitespaces).isEmpty || credentialsPassword.isEmpty)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear {
                            if let creds = CredentialsManager.shared.loadCredentials() {
                                credentialsUsername = creds.username
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GroupBox(L10n.string("settings.workday")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(L10n.string("settings.hours_per_day"))
                                Text(L10n.string("format.hours", settings.workdayHours))
                                    .frame(minWidth: 36, alignment: .trailing)
                                Stepper(
                                    "",
                                    value: workdayHoursBinding,
                                    in: 4...12,
                                    step: 0.5
                                )
                            }

                            Text(L10n.string("settings.workday_help"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(L10n.string("settings.workday_default"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GroupBox(L10n.string("settings.general")) {
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

                            Text(L10n.string("settings.log_level_help"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n.string("settings.close")) {
                    AppLogger.info("User: Settings Close tapped")
                    let trimmed = kotURLText.trimmingCharacters(in: .whitespacesAndNewlines)
                    AppLogger.verbose("Settings: Close tapped — kotURLText.trimmed=\(trimmed.isEmpty ? "(empty)" : trimmed)")
                    SettingsWindowController.shared.setCurrentURLString(trimmed)
                    let msg = AppSettings.kotURLValidationError(trimmed: trimmed)
                    AppLogger.verbose("Settings: Close — validator result=\(msg ?? "nil"), blocking=\(msg != nil)")
                    urlValidationMessage = msg
                    if msg != nil {
                        AppLogger.verbose("Settings: Close — keeping window open, setting red text and focus")
                        urlFieldFocused = true
                        return
                    }
                    AppLogger.verbose("Settings: Close — valid, closing window (timecard sync runs in windowWillClose if credentials present)")
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
                .padding(12)
                .padding(.trailing, 12)
            }
        }
        .frame(minWidth: 480, minHeight: 380)
        .onAppear {
            kotURLText = settings.effectiveKotBaseURL
            let trimmed = settings.effectiveKotBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = AppSettings.kotURLValidationError(trimmed: trimmed)
            AppLogger.verbose("Settings: onAppear — effectiveURL=\(trimmed.isEmpty ? "(empty)" : trimmed), validationError=\(msg ?? "nil")")
            urlValidationMessage = msg
            SettingsWindowController.shared.setCurrentURLString(trimmed)
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsFocusURLField)) { _ in
            let trimmed = kotURLText.trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = AppSettings.kotURLValidationError(trimmed: trimmed)
            AppLogger.verbose("Settings: onReceive(settingsFocusURLField) — setting red text and focus, msg=\(msg ?? "nil")")
            urlValidationMessage = msg
            SettingsWindowController.shared.setValidationError(msg)
            urlFieldFocused = true
        }
    }
}

