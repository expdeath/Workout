import Foundation
import Security

/// Keychain access for the secrets the invite-code era stored on device
/// (Gemini key, GitHub token). Both now live in Firestore (config/shared,
/// accounts/{id}.github); AppState reads these once to carry them over,
/// then removes them.
enum Keychain {
    private static let service = "com.expdeath.CoachApp"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Wipes every secret this app has stored — used by wipeLocal() on
    /// sign-out / account switch (mirrors src/utils/account.js).
    static func removeAll() {
        for key in ["gemini-api-key", "gh-token"] {
            remove(key)
        }
    }
}
