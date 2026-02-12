import Foundation
import Security

struct Credentials {
    let username: String
    let password: String
}

/// Production uses Keychain only; dev uses UserDefaults (dev keys only). Credentials never shared between builds.
final class CredentialsManager: ObservableObject {
    static let shared = CredentialsManager()

    @Published var username: String = ""
    @Published var hasStoredCredentials: Bool = false
    /// Set when Keychain fails in the production app so the UI can show a clear error.
    @Published var keychainErrorMessage: String?

    private let service = "JokerOfTime"
    private let account = "default"

    private static let devUsernameKey = "JokerOfTime.Dev.Username"
    private static let devPasswordKey = "JokerOfTime.Dev.Password"

    private init() {
        if let creds = loadCredentials() {
            username = creds.username
            hasStoredCredentials = true
        }
    }

    func loadCredentials() -> Credentials? {
        if AppEnvironment.isLocal {
            return loadFromDevStore()
        }
        return loadFromKeychainOnly()
    }

    func saveCredentials(username: String, password: String) -> Bool {
        clearKeychainError()
        if AppEnvironment.isLocal {
            saveToDevStore(username: username, password: password)
            self.username = username
            self.hasStoredCredentials = true
            return true
        }
        if saveToKeychain(username: username, password: password) {
            self.username = username
            self.hasStoredCredentials = true
            return true
        }
        setKeychainError(L10n.string("credentials.error.save_failed"))
        return false
    }

    func clearCredentials() {
        clearKeychainError()
        if AppEnvironment.isLocal {
            deleteFromDevStore()
        } else {
            deleteFromKeychain()
        }
        AppLogger.info("Credentials: cleared")
        DispatchQueue.main.async {
            // If user already saved new credentials before this async ran, don't overwrite or post (avoids wiping state after save-after-clear).
            if self.loadCredentials() == nil {
                self.username = ""
                self.hasStoredCredentials = false
                NotificationCenter.default.post(name: .credentialsCleared, object: nil)
            }
        }
    }

    // MARK: - Dev store (UserDefaults; dev only — production must NEVER store credentials in UserDefaults)

    private func loadFromDevStore() -> Credentials? {
        precondition(AppEnvironment.isLocal, "Production must never read credentials from UserDefaults")
        guard let u = UserDefaults.standard.string(forKey: Self.devUsernameKey),
              let p = UserDefaults.standard.string(forKey: Self.devPasswordKey),
              !u.isEmpty else { return nil }
        return Credentials(username: u, password: p)
    }

    private func saveToDevStore(username: String, password: String) {
        precondition(AppEnvironment.isLocal, "Production must never store credentials in UserDefaults")
        UserDefaults.standard.set(username, forKey: Self.devUsernameKey)
        UserDefaults.standard.set(password, forKey: Self.devPasswordKey)
        AppLogger.debug("Credentials: saved to dev store for user \(username)")
    }

    private func deleteFromDevStore() {
        precondition(AppEnvironment.isLocal, "Production must never store credentials in UserDefaults")
        UserDefaults.standard.removeObject(forKey: Self.devUsernameKey)
        UserDefaults.standard.removeObject(forKey: Self.devPasswordKey)
    }

    // MARK: - Keychain (production only)

    private func loadFromKeychainOnly() -> Credentials? {
        let keychainResult = loadFromKeychain()
        if let creds = keychainResult.creds {
            clearKeychainError()
            return creds
        }
        switch keychainResult.status {
        case errSecItemNotFound:
            clearKeychainError()
        case errSecSuccess:
            setKeychainError(L10n.string("credentials.error.corrupted"))
            AppLogger.error("Credentials: Keychain item corrupt or unreadable")
        case errSecMissingEntitlement:
            setKeychainError(L10n.string("credentials.error.not_allowed"))
            AppLogger.error("Credentials: Keychain missing entitlement (status=\(keychainResult.status))")
        default:
            setKeychainError(L10n.string("credentials.error.unavailable"))
            AppLogger.error("Credentials: Keychain read failed (status=\(keychainResult.status))")
        }
        return nil
    }

    // MARK: - Keychain

    private func loadFromKeychain() -> (creds: Credentials?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let existingItem = item as? [String: Any],
              let passwordData = existingItem[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8),
              let usernameData = existingItem[kSecAttrGeneric as String] as? Data,
              let username = String(data: usernameData, encoding: .utf8) else {
            return (nil, status)
        }
        return (Credentials(username: username, password: password), status)
    }

    private func saveToKeychain(username: String, password: String) -> Bool {
        deleteFromKeychain()
        let usernameData = username.data(using: .utf8) ?? Data()
        let passwordData = password.data(using: .utf8) ?? Data()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrGeneric as String: usernameData,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess {
            AppLogger.debug("Credentials: saved for user \(username)")
            return true
        }
        AppLogger.error("Credentials: Keychain save failed (status=\(status))")
        return false
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - User-facing error

    private func setKeychainError(_ message: String) {
        DispatchQueue.main.async {
            self.keychainErrorMessage = message
        }
    }

    private func clearKeychainError() {
        keychainErrorMessage = nil
    }
}

