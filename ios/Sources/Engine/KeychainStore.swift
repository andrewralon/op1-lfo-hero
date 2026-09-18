import Foundation
import Security

/// Persists a single blob of data in the Keychain rather than `UserDefaults`.
///
/// Unlike `UserDefaults`, Keychain items are not stored inside the app's sandbox container, so
/// they survive the app being deleted and reinstalled on the same device — only an explicit
/// delete or a full device erase ("Erase All Content and Settings") removes them. That's the
/// property saved LFO chips need: they were getting wiped by ordinary reinstalls during
/// development, and `UserDefaults` has no way to survive that without iCloud sync.
enum KeychainStore {
    private static let service = "com.andrewralon.op1-lfo-hero.settings"

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Upsert: most items already exist after the first save, so try update first and only add
    /// on a fresh account.
    static func save(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        // ThisDeviceOnly: excluded from encrypted backups/iCloud restore-to-new-device, which is
        // the "no iCloud" half of the requirement — it still survives a plain delete+reinstall.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
