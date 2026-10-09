import Foundation

/// Small non-secret settings — the UserDefaults counterpart to the
/// Keychain wrapper. Mirrors the handful of plain localStorage keys in
/// the web app that aren't secrets (GitHub repo path, account label,
/// last-sync info, cached weekly/monthly AI reports).
enum Defaults {
    private static let d = UserDefaults.standard
    private static let prefix = "coach."

    static func string(_ key: String) -> String? { d.string(forKey: prefix + key) }
    static func set(_ value: String?, for key: String) {
        if let value { d.set(value, forKey: prefix + key) } else { d.removeObject(forKey: prefix + key) }
    }

    static func codable<T: Codable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = d.data(forKey: prefix + key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func setCodable<T: Codable>(_ value: T?, for key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            d.removeObject(forKey: prefix + key)
            return
        }
        d.set(data, forKey: prefix + key)
    }

    /// Removes every coach.* default — used by wipeLocal().
    static func removeAll() {
        for key in d.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            d.removeObject(forKey: key)
        }
    }
}
