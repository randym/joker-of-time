import Foundation

enum L10n {
    private static let bundle: Bundle = {
        let main = Bundle.main
        let code = resolvedLanguageCode(main: main)
        guard let url = main.url(forResource: code, withExtension: "lproj"),
              let b = Bundle(url: url) else {
            return main
        }
        return b
    }()

    private static func resolvedLanguageCode(main: Bundle) -> String {
        if AppEnvironment.isLocal,
           let envLocale = ProcessInfo.processInfo.environment["LOCALE"]?.trimmingCharacters(in: .whitespaces).lowercased(),
           !envLocale.isEmpty {
            let two = String(envLocale.prefix(2))
            if two == "ja" || two == "en" { return two }
        }
        return main.preferredLocalizations.first.map { languageCode($0) } ?? "en"
    }

    private static func languageCode(_ locale: String) -> String {
        let t = locale.prefix(2)
        return String(t)
    }

    static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}
