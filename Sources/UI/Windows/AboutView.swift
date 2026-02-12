import SwiftUI
import AppKit

struct AboutView: View {
    let status: String
    let host: String
    let username: String?
    let nodeVersion: String

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
    private var versionLine: String {
        L10n.string("about.version", version, build)
    }
    private var detailsLines: [String] {
        let env = AppEnvironment.current
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let loggedIn = username.map { L10n.string("about.logged_in_as", $0) } ?? L10n.string("about.not_logged_in")
        return [
            L10n.string("about.build", env),
            L10n.string("about.os", os),
            L10n.string("about.node", nodeVersion),
            L10n.string("about.status", status),
            L10n.string("about.host", host),
            loggedIn,
        ]
    }

    private var appIcon: NSImage? {
        var icon: NSImage?
        if let url = Bundle.main.url(forResource: "JokerOfTime", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            icon = img
        }
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
        if icon == nil {
            icon = NSImage(named: "JokerOfTime") ?? NSImage(named: "AppIcon")
        }
        return icon ?? NSApplication.shared.applicationIconImage
    }

    private let iconSize: CGFloat = 128
    private let iconCornerRadius: CGFloat = 128 * 0.2237

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            if let img = appIcon {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius))
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.string("about.app_name"))
                    .font(.system(size: 22, weight: .bold))

                Text(versionLine)
                    .font(.system(size: NSFont.smallSystemFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(detailsLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: NSFont.smallSystemFontSize))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 10)

                Text(L10n.string("about.disclaimer"))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                HStack {
                    Spacer()
                    Button(L10n.string("button.ok")) {
                        AppLogger.info("User: About OK")
                        NSApplication.shared.keyWindow?.close()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 280, alignment: .leading)
        }
        .padding(24)
    }
}
